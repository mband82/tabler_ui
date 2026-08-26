// Builds the Explorer tab's markup: the directory hierarchy derived from
// the workspace's flat path map (docs/lib/tabler_ui/docs/editor/contract.rb's
// "Workspace" section -- "a flat path => file map, hierarchy derived by
// splitting on '/', the Git approach"), plus each file's own row.
//
// Reuses the docs sidebar's own collapsible-category markup convention
// (docs/app/views/tabler_ui/docs/shared/_sidebar_category.html.erb) --
// data-bs-toggle="collapse" plus data-controller="tabler-ui--collapse", the
// MAIN engine's own already-registered controller
// (app/javascript/controllers/tabler_ui/collapse_controller.js, wired up by
// app/assets/javascripts/tabler_ui.js, loaded by every host) -- rather than
// a second collapse implementation of our own (rule 6, CLAUDE.md).
//
// Pure functions only -- the controller owns all DOM writes and event
// wiring, and reads back `data-editor-path` on click.
import { basename, isPartial, isLayout } from "controllers/tabler_ui/docs/editor/workspace"
import { escapeHtml } from "controllers/tabler_ui/docs/editor/html_escape"

function slug(path) {
  return path.replace(/[^a-zA-Z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "root"
}

// Builds { path, name, dirs: {name => node}, files: [path] } from the
// workspace's flat `files`/`directories` -- mirrors
// Workspace#implied_directories/#normalize_directories on the server: a
// directory implied by some file's own path doesn't need its own entry
// here either, it falls out of walking the file paths themselves.
function buildDirTree(paths, directories) {
  const root = { path: "", name: "", dirs: {}, files: [] }

  const ensureDir = (path) => {
    if (path === "") return root

    const segments = path.split("/")
    let node = root
    let current = ""
    segments.forEach((segment) => {
      current = current ? `${current}/${segment}` : segment
      if (!node.dirs[segment]) {
        node.dirs[segment] = { path: current, name: segment, dirs: {}, files: [] }
      }
      node = node.dirs[segment]
    })
    return node
  }

  directories.forEach((dir) => ensureDir(dir))
  paths.forEach((path) => ensureDir(dirname(path)).files.push(path))

  return root
}

function dirname(path) {
  const idx = path.lastIndexOf("/")
  return idx === -1 ? "" : path.slice(0, idx)
}

function fileRowHtml(path, openPath) {
  const name = basename(path)
  const active = path === openPath ? " active" : ""
  const badge = isPartial(path)
    ? '<span class="badge bg-purple-lt text-purple ms-1">partial</span>'
    : (isLayout(path) ? '<span class="badge bg-azure-lt text-azure ms-1">layout</span>' : "")

  return `
    <div class="list-group-item list-group-item-action py-1 d-flex align-items-center justify-content-between docs-editor-explorer-file${active}">
      <span class="text-truncate flex-fill" role="button"
            data-action="click->tabler-ui--docs-editor#selectFile" data-editor-path="${escapeHtml(path)}">
        ${escapeHtml(name)}${badge}
      </span>
      <span class="btn-list ms-1">
        <button type="button" class="btn btn-sm btn-icon btn-ghost-secondary" title="Rename"
                data-action="click->tabler-ui--docs-editor#renameFile" data-editor-path="${escapeHtml(path)}">&#9998;</button>
        <button type="button" class="btn btn-sm btn-icon btn-ghost-secondary" title="Duplicate"
                data-action="click->tabler-ui--docs-editor#duplicateFile" data-editor-path="${escapeHtml(path)}">&#10697;</button>
        <button type="button" class="btn btn-sm btn-icon btn-ghost-danger" title="Delete"
                data-action="click->tabler-ui--docs-editor#deleteFile" data-editor-path="${escapeHtml(path)}">&times;</button>
      </span>
    </div>
  `
}

function dirHtml(node, openPath, depth) {
  const paneId = `docs-editor-explorer-${slug(node.path)}`
  const childDirs = Object.values(node.dirs).sort((a, b) => a.name.localeCompare(b.name))
  const inner = `
    ${childDirs.map((child) => dirHtml(child, openPath, depth + 1)).join("")}
    ${node.files.slice().sort().map((path) => fileRowHtml(path, openPath)).join("")}
  `

  return `
    <div class="mb-1">
      <button type="button"
              class="btn btn-link btn-sm w-100 d-flex align-items-center gap-1 px-0 py-1 text-secondary text-decoration-none"
              data-bs-toggle="collapse" data-bs-target="#${paneId}" aria-expanded="true" aria-controls="${paneId}">
        <span class="text-truncate">${escapeHtml(node.name)}/</span>
      </button>
      <div id="${paneId}" class="collapse show ps-3" data-controller="tabler-ui--collapse">
        ${inner}
      </div>
    </div>
  `
}

// @param index {paths, directories, open} -- see workspace.js#buildIndex.
export function explorerHtml(index) {
  if (!index || !index.paths || index.paths.length === 0) {
    return '<p class="text-secondary small mb-0">No files yet -- use "New file" above to start.</p>'
  }

  const tree = buildDirTree(index.paths, index.directories || [])
  const rootDirs = Object.values(tree.dirs).sort((a, b) => a.name.localeCompare(b.name))

  return `
    <div class="docs-editor-explorer">
      ${rootDirs.map((child) => dirHtml(child, index.open, 0)).join("")}
      ${tree.files.slice().sort().map((path) => fileRowHtml(path, index.open)).join("")}
    </div>
  `
}
