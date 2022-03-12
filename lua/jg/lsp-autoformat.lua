local M = {}
local l = {}

M.formatting_clients = {}
l.organize_imports_clients = { 'gopls' }

function M.setup(clients)
  M.formatting_clients = clients or {}

  local pattern = table.concat(vim.tbl_keys(M.formatting_clients), ',')

  vim.cmd([[
    augroup lsp-autoformat
      au!
      au! BufWritePre ]] .. pattern .. [[ lua require('jg.lsp-autoformat').on_buf_write_pre()
    augroup END
  ]])
end

function M.on_buf_write_pre()
  if l.auto_formatting_enabled(vim.fn.expand('<afile>:t')) then
    M.buf_formatting()
  end
end

function l.auto_formatting_enabled(file_name)
  return l.get_formatting_clients(file_name) ~= nil
end

function l.starts_with(str, prefix)
  return string.sub(str, 1, string.len(prefix)) == prefix
end

function l.ends_with(str, postfix)
  return postfix == '' or str:sub(-#postfix) == postfix
end

function l.match_pattern(pattern, file_name)
  if l.starts_with(pattern, '*') then
    return l.ends_with(file_name, string.sub(pattern, 2))
  elseif l.ends_with(pattern, '*') then
    return l.starts_with(file_name, string.sub(pattern, 1, #pattern - 1))
  end

  return file_name == pattern
end

function l.get_formatting_clients(file_name)
  for pattern, clients in pairs(M.formatting_clients) do
    if l.match_pattern(pattern, file_name) then
      return clients
    end
  end
end

function M.buf_formatting(client_names)
  client_names = client_names or l.get_formatting_clients(vim.fn.expand('%:t'))

  local client = l.select_client('textDocument/formatting', client_names)
  if client == nil then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local encoding = vim.api.nvim_buf_get_option(bufnr, 'fileencoding')

  if vim.tbl_contains(l.organize_imports_clients, client.name) then
    l.request_organize_imports(client, bufnr, encoding)
  end

  l.request_formatting(client, bufnr, encoding)
end

function l.request_formatting(client, bufnr, encoding)
  local params = vim.lsp.util.make_formatting_params(nil)

  l.request(client, 'textDocument/formatting', params, bufnr, function(result)
    vim.lsp.util.apply_text_edits(result, bufnr, encoding)
  end)
end

-- organize imports for gopls
function l.request_organize_imports(client, bufnr, encoding)
  local params = vim.lsp.util.make_range_params()
  params.context = { source = { organizeImports = true } }

  l.request(client, 'textDocument/codeAction', params, bufnr, function(result)
    for _, r in ipairs(result) do
      vim.lsp.util.apply_workspace_edit(r.edit, encoding)
    end
  end)
end

function l.request(client, method, params, bufnr, apply_fn)
  local response = client.request_sync(method, params, 1000, bufnr)
  if response ~= nil and response.result ~= nil then
    apply_fn(response.result)
  end
end

function l.select_client(method, client_names)
  local clients = vim.tbl_filter(function(client)
    return client.supports_method(method)
  end, vim.tbl_values(vim.lsp.buf_get_clients()))

  table.sort(clients, function(a, b)
    return a.name < b.name
  end)

  if client_names ~= nil then
    for _, client_name in ipairs(client_names) do
      local client = vim.tbl_filter(function(client)
        return client.name == client_name
      end, clients)[1]

      if client ~= nil then
        return client
      end
    end
  end

  return nil
end

return M
