async page => {
  // Поиск анимаций Mixamo через внутренний API страницы (сессия пользователя). Токен не выводится.
  const queries = ["standing melee attack", "one hand club combo", "one hand sword combo",
                   "shotgun", "pistol", "gunplay", "shooting", "dual pistol"];
  return await page.evaluate(async (queries) => {
    const h = { "Authorization": "Bearer " + localStorage.access_token, "X-Api-Key": "mixamo2", "Accept": "application/json" };
    const out = {};
    const prim = await (await fetch("/api/v1/characters/primary", { headers: h })).json();
    out.primary = { id: prim.primary_character_id, name: prim.primary_character_name };
    for (const q of queries) {
      const r = await fetch(`/api/v1/products?page=1&limit=48&order=&type=Motion%2CMotionPack&query=${encodeURIComponent(q)}`, { headers: h });
      const j = await r.json();
      out[q] = (j.results || []).map(p => `${p.name} | ${p.description} | ${p.id} | ${p.type}`);
    }
    return JSON.stringify(out, null, 1);
  }, queries);
}
