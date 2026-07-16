// file-note.js — QuickAdd user script: "File this…"
//
// Pops a domain menu (Work / Personal / Learning / Archive), an optional type
// picker, and an optional curated topic-tag picker, then moves the active
// note there — setting `domain`/`type`/`tags`/`status` and rewriting
// backlinks (renameFile updates every link that points at the note). Bound
// to ⌘⇧M via the `quickadd:choice:file-this` command.
//
// Filing is purely a domain question now — "what kind of note is this?" is
// answered by the type picker below (project/area/person/reading/note), not
// by which bucket you file into.
//
// Seeded into the vault at `99 Meta/_scripts/file-note.js` by
// scripts/lib/obsidian-apply.sh (seed-only, never overwritten).

module.exports = async ({ app, quickAddApi }) => {
  const file = app.workspace.getActiveFile();
  if (!file) {
    new Notice("No active note to file.");
    return;
  }

  // [label, target folder, domain]. Only 4 buckets — domain is the only
  // filing question left.
  const DESTS = [
    ["💼 Work", "10 Areas/Work", "work"],
    ["🏠 Personal", "10 Areas/Personal", "personal"],
    ["🎓 Learning", "10 Areas/Learning", "learning"],
    ["🗄 Archive", "20 Archive", null],
  ];

  // Types this vault has templates for. Esc/none = leave `type` as-is — use
  // that when re-filing an already-typed note across domains, not promoting
  // a fresh inbox capture.
  const TYPES = ["project", "area", "person", "reading", "meeting", "note"];

  // Curated topic tags — keep it short and edit freely. A tight list beats a
  // sprawling one: consistent tags are what make the tag pane worth clicking.
  const TOPICS = ["dev", "infra", "career", "learning", "reading", "finance", "health", "idea"];

  const dest = await quickAddApi.suggester(
    DESTS.map((d) => d[0]),
    DESTS,
  );
  if (!dest) return; // Esc on the bucket = cancel the whole thing
  const [, folder, domain] = dest;

  let newType = null;
  if (folder !== "20 Archive") {
    try {
      newType = await quickAddApi.suggester(TYPES, TYPES);
    } catch (e) {
      newType = null;
    }
  }

  // Optional topic tags. Esc / none selected = file without touching tags.
  let picked = [];
  try {
    picked = (await quickAddApi.checkboxPrompt(TOPICS)) ?? [];
  } catch (e) {
    picked = [];
  }

  await app.fileManager.processFrontMatter(file, (fm) => {
    const wasInbox = (fm.type ?? "inbox") === "inbox";

    // Drop the "inbox" tag on the way out; merge in the picked topics.
    const base = (fm.tags ?? []).filter((t) => t !== "inbox");
    const merged = [...new Set([...base, ...picked])];
    if (merged.length) fm.tags = merged;
    else delete fm.tags;

    if (domain) fm.domain = domain;
    if (newType) fm.type = newType;

    // Only stamp status="filed" when promoting a fresh inbox capture — don't
    // clobber a project/area's own active/paused/done lifecycle status when
    // just re-filing it across domains.
    if (wasInbox || newType) fm.status = "filed";
  });

  if (!app.vault.getAbstractFileByPath(folder)) {
    await app.vault.createFolder(folder);
  }
  await app.fileManager.renameFile(file, `${folder}/${file.name}`);

  const tagNote = picked.length ? ` · ${picked.map((t) => "#" + t).join(" ")}` : "";
  new Notice(`Filed → ${folder}${tagNote}`);
};
