local openai = require("codecompanion.adapters.openai")

local log_file = vim.fn.expand("/tmp/neovim_debug.log")

local function log_message(message)
  local file = io.open(log_file, "a")
  if file then
    file:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
    file:close()
  end
end

---@class Mistral.Adapter: CodeCompanion.Adapter
return {
  name = "mistral",
  formatted_name = "Mistral",
  roles = {
    llm = "assistant",
    user = "user",
    tool = "tool",
  },
  opts = {
    stream = true,
    tools = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = true,
  },
  url = "https://api.mistral.ai/v1/chat/completions",
  env = {
    api_key = "MISTRAL_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
  },
  handlers = {
    --- Use the OpenAI adapter for the bulk of the work
    --stream_options does not work with mistral, hence the scaled down function.
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      return true
    end,
    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    form_messages = function(self, messages)
      messages = vim
          .iter(messages)
          :map(function(m)
            local model = self.schema.model.default
            if type(model) == "function" then
              model = model(self)
            end

            -- Ensure tool_calls are clean
            if m.tool_calls then
              m.tool_calls = vim
                  .iter(m.tool_calls)
                  :map(function(tool_call)
                    return {
                      id = tool_call.id,
                      ["function"] = tool_call["function"],
                      type = tool_call.type,
                    }
                  end)
                  :totable()
            end

            return {
              role = m.role,
              content = m.content,
              tool_calls = m.tool_calls,
              tool_call_id = m.tool_call_id,
            }
          end)
          :totable()
      log_message("Original messages array: " .. vim.inspect(messages))
      -- New logic to remove user messages following tool messages
      local i = 1
      while i < #messages do
        if messages[i].role == "tool" and messages[i + 1] and messages[i + 1].role == "user" then
          table.remove(messages, i + 1)
        else
          i = i + 1
        end
      end
      -- if #messages >= 2 then
      --   local last_index = #messages
      --   local second_last_index = last_index - 1
      --
      --   if messages[second_last_index].role == "tool" and messages[last_index].role == "user" then
      --     -- Remove the last message if it's a user message
      --     table.remove(messages, last_index)
      --   end
      -- end

      log_message("Modified messages array: " .. vim.inspect(messages))
      return { messages = messages }
    end,
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc =
      "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "mistral-small-latest",
      choices = {
        -- Premier models
        "mistral-large-latest",
        "pixtral-large-latest",
        "mistral-saba-latest",
        "codestral-latest",
        "ministral-8b-latest",
        "ministral-3b-latest",
        -- Free models, latest
        "mistral-small-latest",
        "pixtral-12b-2409",
        -- Free models, research
        "open-mistral-nemo",
        "open-codestral-mamba",
      },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc =
      "What sampling temperature to use, we recommend between 0.0 and 0.7. Higher values like 0.7 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 1.5, "Must be between 0 and 1.5"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc =
      "Nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc =
      "The maximum number of tokens to generate in the completion. The token count of your prompt plus max_tokens cannot exceed the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    ---@type CodeCompanion.Schema
    stop = {
      order = 5,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Stop generation if this token is detected. Or if one of these tokens is detected when providing an array.",
      validate = function(l)
        return #l >= 1, "Must have more than 1 element"
      end,
    },
    ---@type CodeCompanion.Schema
    random_seed = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "The seed to use for random sampling. If set, different calls will generate deterministic results.",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    ---@type CodeCompanion.Schema
    presence_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc =
      "Determines how much the model penalizes the repetition of words or phrases. A higher presence penalty encourages the model to use a wider variety of words and phrases, making the output more diverse and creative.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    frequency_penalty = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc =
      "Penalizes the repetition of words based on their frequency in the generated text. A higher frequency penalty discourages the model from repeating words that have already appeared frequently in the output, promoting diversity and reducing repetition.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    n = {
      order = 9,
      mapping = "parameters",
      type = "number",
      default = 1,
      desc = "Number of completions to return for each request, input tokens are only billed once.",
    },
    ---@type CodeCompanion.Schema
    safe_prompt = {
      order = 10,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = false,
      desc = "Whether to inject a safety prompt before all conversations.",
    },
  },
}
