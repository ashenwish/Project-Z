async page => {
  // Экспорт анимации Mixamo (без скина, 30 fps, без упрощения ключей) в Collada.
  // Возвращает временную ссылку на архив. Токен не выводится.
  const ids = (process.env.MX_IDS || "").split(",").filter(Boolean);
  return await page.evaluate(async (ids) => {
    const h = { "Authorization": "Bearer " + localStorage.access_token, "X-Api-Key": "mixamo2",
                "Accept": "application/json", "Content-Type": "application/json" };
    const sleep = ms => new Promise(r => setTimeout(r, ms));
    const charId = (await (await fetch("/api/v1/characters/primary", { headers: h })).json()).primary_character_id;
    const out = [];
    for (const id of ids) {
      const prod = await (await fetch(`/api/v1/products/${id}?similar=0&character_id=${charId}`, { headers: h })).json();
      const g = prod.details.gms_hash;
      const params = (g.params || []).map(p => p[1]).join(",");
      const body = {
        character_id: charId, product_name: prod.description, type: "Motion",
        preferences: { format: "dae_mixamo", skin: "false", fps: "30", reducekf: "0" },
        gms_hash: [{ "model-id": g["model-id"], mirror: false, trim: g.trim, overdrive: 0,
                     params: params, "arm-space": g["arm-space"] || 0, inplace: false }],
      };
      const r = await fetch("/api/v1/animations/export", { method: "POST", headers: h, body: JSON.stringify(body) });
      if (!r.ok) { out.push({ id, error: "export " + r.status + " " + (await r.text()).slice(0, 200) }); continue; }
      let url = null, status = "";
      for (let i = 0; i < 60 && !url; i++) {
        await sleep(2000);
        const m = await (await fetch(`/api/v1/characters/${charId}/monitor`, { headers: h })).json();
        status = m.status;
        if (m.status === "completed") url = m.job_result;
        if (m.status === "failed") break;
      }
      out.push({ id, name: prod.name, description: prod.description, status, url });
    }
    return JSON.stringify(out);
  }, ids);
}
