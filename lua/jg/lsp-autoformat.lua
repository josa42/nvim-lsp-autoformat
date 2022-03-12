local M = {}
local l = {}

M.formatting_clients = {}
l.organize_imports_clients = { 'gopls' }

function M.setup(clients)
  M.formatting_clients = clients or {}

  local pattern = table.concat(l.auto_formatting_pattern(), ',')

  vim.cmd([[
    augroup lsp-autoformat
      au!
      au! BufWritePre ]] .. pattern .. [[ lua require('jg.lsp-autoformat').on_buf_write_pre()
    augroup END
  ]])
end

function M.on_buf_write_pre()
  if l.auto_formatting_enabled(vim.fn.expand('<afile>:t'), vim.fn.expand('<afile>:e')) then
    M.buf_formatting()
  end
end

function l.auto_formatting_enabled(name, ext)
  for v in pairs(M.formatting_clients) do
    if v == name or v == ext then
      return true
    end
  end

  return false
end

function l.auto_formatting_pattern()
  local pattern = {}
  for ext in pairs(M.formatting_clients) do
    table.insert(pattern, '*.' .. ext)
    table.insert(pattern, ext)
  end

  return pattern
end

function l.get_formatting_clients(ext)
  for k, clients in pairs(M.formatting_clients) do
    if k == ext then
      return clients
    end
  end
end

function M.buf_formatting(client_names)
  client_names = client_names or l.get_formatting_clients(vim.fn.expand('%:e'))

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
