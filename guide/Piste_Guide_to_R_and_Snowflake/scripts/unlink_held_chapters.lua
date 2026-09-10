--[[
  Neutralise cross-links that point into chapters the publish profile holds back.

  The curated conference subset (_quarto-publish.yml) omits ~12 chapters, but ~50
  links from the published chapters point *into* them. Left alone every one of
  those is a 404 on the published site. Rewriting them in the shared .qmd source
  would break the full local render instead, so this runs as a profile-scoped
  filter: it keeps the link *text* (which reads as prose -- "see Workspace
  Bootstrap"), drops the anchor, and marks it so a reader knows the target is
  coming rather than missing.

  Held-back paths come from the `held-chapters` metadata key in
  _quarto-publish.yml, so the profile stays the single source of truth. Two
  filter passes, because Pandoc runs Meta *after* inline elements within a
  single pass -- with one table the list would still be empty at Link time.
]]

local held = {}

local function collect(m)
  if m["held-chapters"] then
    for _, v in ipairs(m["held-chapters"]) do
      held[#held + 1] = pandoc.utils.stringify(v)
    end
  end
  return m
end

local function is_held(target)
  for _, h in ipairs(held) do
    if target:find(h, 1, true) then return true end
  end
  return false
end

local function unlink(el)
  if #held > 0 and is_held(el.target) then
    local out = {}
    for _, inline in ipairs(el.content) do out[#out + 1] = inline end
    out[#out + 1] = pandoc.Superscript(pandoc.Str("†"))
    return out
  end
end

return {
  { Meta = collect },
  { Link = unlink },
}
