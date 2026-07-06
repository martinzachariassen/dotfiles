// file-note.js — QuickAdd user script: "File this…"
//
// Pops a named menu of PARA destinations, an optional curated topic-tag picker,
// then moves the active note there — setting `domain`/`tags`/`status` and
// rewriting backlinks (renameFile updates every link that points at the note).
// Bound to ⌘⇧M via the `quickadd:choice:file-this` command.
//
// Two axes power findability:
//   • domain (work | personal) — set automatically by the life-area buckets.
//   • tags   — chosen from TOPICS below; edit that one line to taste.
//
// Seeded into the vault at `99 Meta/_scripts/file-note.js` by
// scripts/lib/obsidian-apply.sh (seed-only, never overwritten).

module.exports = async ({ app, quickAddApi }) => {
  const file = app.workspace.getActiveFile();
  if (!file) {
    new Notice("No active note to file.");
    return;
  }

  // [label, target folder, domain]. Labels name the bucket so filing needs no
  // recall of the numbered PARA paths. domain is set only for the life-areas.
  const DESTS = [
    ["💼 Work", "30 Areas/31 Work", "work"],
    ["🏠 Personal", "30 Areas/32 Personal", "personal"],
    ["📁 Project", "20 Projects", null],
    ["📚 Resource", "40 Resources", null],
    ["🗄 Archive", "50 Archive", null],
  ];

  // Curated topic tags — keep it short and edit freely. A tight list beats a
  // sprawling one: consistent tags are what make the tag pane worth clicking.
  const TOPICS = ["dev", "infra", "career", "learning", "reading", "finance", "health", "idea"];

  const dest = await quickAddApi.suggester(
    DESTS.map((d) => d[0]),
    DESTS,
  );
  if (!dest) return; // Esc on the bucket = cancel the whole thing
  const [, folder, domain] = dest;

  // Optional topic tags. Esc / none selected = file without touching tags.
  let picked = [];
  try {
    picked = (await quickAddApi.checkboxPrompt(TOPICS)) ?? [];
  } catch (e) {
    picked = [];
  }

  await app.fileManager.processFrontMatter(file, (fm) => {
    // Drop the "inbox" tag on the way out; merge in the picked topics.
    const base = (fm.tags ?? []).filter((t) => t !== "inbox");
    const merged = [...new Set([...base, ...picked])];
    if (merged.length) fm.tags = merged;
    else delete fm.tags;
    if (domain) fm.domain = domain;
    fm.status = "filed";
  });

  if (!app.vault.getAbstractFileByPath(folder)) {
    await app.vault.createFolder(folder);
  }
  await app.fileManager.renameFile(file, `${folder}/${file.name}`);

  const tagNote = picked.length ? ` · ${picked.map((t) => "#" + t).join(" ")}` : "";
  new Notice(`Filed → ${folder}${tagNote}`);
};
