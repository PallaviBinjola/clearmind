// frontend/js/app.js  —  Clearmind complete frontend logic

const API = "http://localhost:5000";
const PAL = ["#6C63FF","#3DFFA0","#FFB347","#FF6B8A","#22D4EE","#A78BFA"];

// ── STATE ─────────────────────────────────────────────────────────────────────
const S = {
  token: localStorage.getItem("cm_token") || null,
  sessionId: localStorage.getItem("cm_sid") || null,
  userName: localStorage.getItem("cm_name") || "",
  isGuest: localStorage.getItem("cm_guest") === "1",
  userGoals: [],
  msgCount: 0,
  lastExercise: null,
  lastEmotion: "okay",
};

const diaryEntries = [];
let lChart = null, dChart = null;

// ── UTILS ─────────────────────────────────────────────────────────────────────
function esc(s) { return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }
async function post(path, data, useAuth) {
  const headers = { "Content-Type": "application/json" };
  if (useAuth && S.token) headers["Authorization"] = `Bearer ${S.token}`;
  const r = await fetch(API + path, { method:"POST", headers, body:JSON.stringify(data) });
  return r.json();
}
async function get(path, useAuth) {
  const headers = {};
  if (useAuth && S.token) headers["Authorization"] = `Bearer ${S.token}`;
  const r = await fetch(API + path, { headers });
  return r.json();
}

// ── NAVIGATION ────────────────────────────────────────────────────────────────
function go(id) {
  document.querySelectorAll(".page").forEach(p => p.classList.remove("active"));
  document.getElementById(id).classList.add("active");
}

function enterApp() {
  // Ensure we have a session before entering app
  if (!S.sessionId) {
    _createGuestSession().then(() => _goApp());
  } else {
    _goApp();
  }
}

function _goApp() {
  go("pg-app");
  document.getElementById("sb-av").textContent = (S.userName || "G")[0].toUpperCase();
  document.getElementById("sb-av").title = S.userName || "Guest";
  updateWelcome();
  checkHealth();
}

function showPanel(name) {
  document.querySelectorAll(".panel").forEach(p => p.classList.remove("active"));
  document.querySelectorAll(".sbbtn").forEach(b => b.classList.remove("active"));
  document.getElementById("pn-" + name).classList.add("active");
  const sb = document.getElementById("sb-" + name);
  if (sb) sb.classList.add("active");
  if (name === "insights") loadInsights();
  if (name === "tools") updateToolSuggestion();
}

// ── AUTO-LOGIN on page load ───────────────────────────────────────────────────
window.addEventListener("DOMContentLoaded", async () => {
  if (S.token && S.sessionId) {
    // Verify token is still valid
    try {
      const me = await get("/api/auth/me", true);
      if (me.username) {
        S.userName = me.name || me.username;
        S.sessionId = me.sessionId;
        S.userGoals = me.goals || [];
        localStorage.setItem("cm_sid", S.sessionId);
        localStorage.setItem("cm_name", S.userName);
        enterApp();
        return;
      }
    } catch {}
    // Token invalid — clear and show landing
    clearAuth();
  }
  go("pg-land");
});

function clearAuth() {
  S.token = null; S.sessionId = null; S.userName = ""; S.isGuest = false;
  localStorage.removeItem("cm_token");
  localStorage.removeItem("cm_sid");
  localStorage.removeItem("cm_name");
  localStorage.removeItem("cm_guest");
}

// ── AUTH ──────────────────────────────────────────────────────────────────────
function showErr(id, msg) {
  const el = document.getElementById(id);
  el.textContent = msg; el.classList.add("show");
  setTimeout(() => el.classList.remove("show"), 4000);
}

async function doLogin() {
  const username = document.getElementById("li-user").value.trim();
  const password = document.getElementById("li-pass").value.trim();
  if (!username || !password) return showErr("li-err", "Please fill in both fields.");
  try {
    const r = await post("/api/auth/login", { username, password });
    if (r.error) return showErr("li-err", r.error);
    S.token = r.token; S.sessionId = r.sessionId;
    S.userName = r.name || r.username; S.userGoals = r.goals || [];
    localStorage.setItem("cm_token", S.token);
    localStorage.setItem("cm_sid", S.sessionId);
    localStorage.setItem("cm_name", S.userName);
    enterApp();
  } catch { showErr("li-err", "Connection failed — is the server running?"); }
}

async function doRegister() {
  const name = document.getElementById("rg-name").value.trim();
  const username = document.getElementById("rg-user").value.trim();
  const password = document.getElementById("rg-pass").value.trim();
  if (!name || !username || !password) return showErr("rg-err", "Please fill in all fields.");
  try {
    const r = await post("/api/auth/register", { name, username, password });
    if (r.error) return showErr("rg-err", r.error);
    S.token = r.token; S.sessionId = r.sessionId;
    S.userName = r.name || r.username; S.userGoals = r.goals || [];
    localStorage.setItem("cm_token", S.token);
    localStorage.setItem("cm_sid", S.sessionId);
    localStorage.setItem("cm_name", S.userName);
    // Show onboarding for new users
    go("pg-onboard");
  } catch { showErr("rg-err", "Connection failed — is the server running?"); }
}

function doLogout() {
  if (S.token) post("/api/auth/logout", {}, true).catch(() => {});
  clearAuth();
  // Reset app state
  S.msgCount = 0; S.lastExercise = null; S.lastEmotion = "okay";
  diaryEntries.length = 0;
  document.getElementById("chat-feed").innerHTML = `
    <div class="cdiv">Today</div>
    <div class="mrow"><div class="av av-b">A</div>
    <div class="mstack"><div class="bub bot" id="wb">Hello — I'm Aria. I'm here to listen, not just respond. What's on your mind today?</div></div></div>`;
  document.getElementById("ins-empty").style.display = "flex";
  document.getElementById("ins-content").style.display = "none";
  document.getElementById("dlist").innerHTML = `<div class="empty-state" style="padding:36px"><div class="es-icon">&#128221;</div><div class="es-title">No entries yet</div></div>`;
  if (lChart) { lChart.destroy(); lChart = null; }
  if (dChart) { dChart.destroy(); dChart = null; }
  go("pg-land");
}

async function goAppAsGuest() {
  clearAuth();
  S.isGuest = true;
  localStorage.setItem("cm_guest", "1");
  await _createGuestSession();
  _goApp();
}

async function _createGuestSession() {
  try {
    const r = await post("/api/session/guest", { name: "Guest" });
    S.sessionId = r.sessionId;
    S.userName = "Guest";
    localStorage.setItem("cm_sid", S.sessionId);
    localStorage.setItem("cm_name", S.userName);
  } catch {
    S.sessionId = "guest-" + Date.now().toString(36);
    S.userName = "Guest";
  }
}

// ── ONBOARDING (after register) ───────────────────────────────────────────────
let obMood = "";
function pickMood(el, m) { document.querySelectorAll(".om").forEach(x => x.classList.remove("on")); el.classList.add("on"); obMood = m; }
function tog(el) { el.classList.toggle("on"); }
function obGo(step) {
  document.querySelectorAll(".obs").forEach(s => s.classList.remove("active"));
  document.getElementById("ob" + step).classList.add("active");
  for (let i = 1; i <= 2; i++) { const b = document.getElementById("op" + i); if (b) b.classList.toggle("on", i <= step); }
}
async function obFinish() {
  S.userGoals = [...document.querySelectorAll("#ob-goals .oc.on")].map(e => e.textContent.trim());
  if (S.token) {
    await post("/api/session/update", { sessionId: S.sessionId, goals: S.userGoals }, true).catch(() => {});
  }
  enterApp();
}

// ── WELCOME ───────────────────────────────────────────────────────────────────
function updateWelcome() {
  const h = new Date().getHours();
  const t = h < 12 ? "morning" : h < 17 ? "afternoon" : "evening";
  const n = S.userName && S.userName !== "Guest" ? S.userName : "there";
  const g = S.userGoals.length ? ` I know you want to work on ${S.userGoals[0].toLowerCase()}.` : "";
  const wb = document.getElementById("wb");
  if (wb) wb.textContent = `Good ${t}, ${n}.${g} I'm Aria — here to listen and understand. What's on your mind today?`;
}

async function checkHealth() {
  try {
    const d = await get("/api/health");
    const badge = document.getElementById("ai-badge");
    if (!badge) return;
    if (d.key_configured) {
      badge.textContent = "OpenRouter AI";
      badge.style.color = "var(--grn)"; badge.style.background = "var(--grna)";
    } else {
      badge.textContent = "Smart AI";
    }
  } catch {}
}

// ── CHAT ──────────────────────────────────────────────────────────────────────
function onKey(e) { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMsg(); } }
function resTA(el) { el.style.height = "auto"; el.style.height = Math.min(el.scrollHeight, 100) + "px"; }

async function sendMsg() {
  const btn = document.getElementById("sbtn"), inp = document.getElementById("cinp");
  const text = inp.value.trim();
  if (!text || btn.disabled) return;
  inp.value = ""; inp.style.height = "auto"; btn.disabled = true;
  document.getElementById("hint").textContent = "Aria is thinking...";
  addUMsg(text); showTyp(true);

  // Ensure we have a session
  if (!S.sessionId) await _createGuestSession();

  const thinkTime = Math.min(600 + text.length * 16, 3000);
  try {
    const [d] = await Promise.all([
      post("/api/chat", { sessionId: S.sessionId, message: text }),
      new Promise(res => setTimeout(res, thinkTime))
    ]);
    S.msgCount++;
    if (d.ml) S.lastEmotion = d.ml.emotion;
    if (d.exercise) S.lastExercise = d.exercise;
    showTyp(false);
    if (d.crisis) addCrisisMsg();
    addBotMsg(d.reply, d.insight, d.exercise, d.ai_source);
    updateChatSub(d.ai_source);
  } catch {
    showTyp(false);
    addBotMsg("Cannot reach the backend. Make sure Flask is running: python backend/app.py", null, null, null);
  }
  btn.disabled = false;
  document.getElementById("hint").textContent = "Python ML analyses every message in real-time";
}

async function quickMood(el, mood) {
  document.querySelectorAll(".mbbtn").forEach(b => b.classList.remove("on"));
  el.classList.add("on");
  const btn = document.getElementById("sbtn");
  if (btn.disabled) return;
  btn.disabled = true;
  document.getElementById("hint").textContent = "Aria is thinking...";
  addUMsg(mood); showTyp(true);
  if (!S.sessionId) await _createGuestSession();
  try {
    const [d] = await Promise.all([
      post("/api/chat", { sessionId: S.sessionId, message: mood }),
      new Promise(res => setTimeout(res, 1200))
    ]);
    S.msgCount++;
    if (d.ml) S.lastEmotion = d.ml.emotion;
    if (d.exercise) S.lastExercise = d.exercise;
    showTyp(false);
    if (d.crisis) addCrisisMsg();
    addBotMsg(d.reply, d.insight, d.exercise, d.ai_source);
    updateChatSub(d.ai_source);
  } catch {
    showTyp(false);
    addBotMsg("Cannot reach backend — run: python backend/app.py", null, null, null);
  }
  btn.disabled = false;
  document.getElementById("hint").textContent = "Python ML analyses every message in real-time";
}

function addUMsg(text) {
  const feed = document.getElementById("chat-feed");
  const row = document.createElement("div"); row.className = "mrow user";
  const init = S.userName ? S.userName[0].toUpperCase() : "U";
  row.innerHTML = `<div class="av av-u">${init}</div><div class="mstack"><div class="bub user">${esc(text)}</div></div>`;
  feed.appendChild(row); scrollFeed();
}

function addBotMsg(text, insight, exercise, aiSource) {
  const feed = document.getElementById("chat-feed");
  const row = document.createElement("div"); row.className = "mrow";
  let html = `<div class="av av-b">A</div><div class="mstack"><div class="bub bot">${esc(text)}</div>`;
  if (insight) {
    html += `<div class="ichip"><div class="iclbl">${esc(insight.title)}</div><div class="ictxt">${esc(insight.text)}</div></div>`;
  }
  if (exercise) {
    const C = {
      breathing: {bg:"rgba(108,99,255,.12)",bd:"rgba(108,99,255,.25)",tc:"#6C63FF"},
      grounding:  {bg:"rgba(61,255,160,.08)",bd:"rgba(61,255,160,.2)",tc:"#3DFFA0"},
      gratitude:  {bg:"rgba(255,179,71,.08)",bd:"rgba(255,179,71,.2)",tc:"#FFB347"},
      journal:    {bg:"rgba(34,212,238,.08)",bd:"rgba(34,212,238,.2)",tc:"#22D4EE"},
    };
    const c = C[exercise.type] || C.breathing;
    const mt = exercise.type === "journal" ? "gratitude" : exercise.type;
    html += `<div class="exchip" style="background:${c.bg};border:1px solid ${c.bd}" onclick="openMod('${mt}')">
      <div class="exico">${esc(exercise.icon)}</div>
      <div><div class="exname" style="color:${c.tc}">${esc(exercise.name)}</div>
      <div class="exwhy" style="color:${c.tc}">${esc(exercise.reason)}</div>
      <div class="excta" style="color:${c.tc}">Tap to open exercise</div></div></div>`;
  }
  html += "</div>";
  row.innerHTML = html; feed.appendChild(row); scrollFeed();
}

function addCrisisMsg() {
  const feed = document.getElementById("chat-feed");
  const div = document.createElement("div"); div.className = "crisis";
  div.innerHTML = "<strong>If you are in crisis or having thoughts of harm, please reach out:</strong><br>iCall (India): <strong>9152987821</strong> &nbsp;|&nbsp; Vandrevala Foundation: <strong>1860-2662-345</strong> (24/7)";
  feed.appendChild(div); scrollFeed();
}

function showTyp(v) { document.getElementById("typ-row").classList.toggle("show", v); if (v) scrollFeed(); }
function scrollFeed() { const f = document.getElementById("chat-feed"); setTimeout(() => f.scrollTop = f.scrollHeight, 60); }
function updateChatSub(src) {
  const n = S.msgCount;
  const badge = src && src.startsWith("openrouter") ? " · OpenRouter" : " · Smart AI";
  document.getElementById("chat-sub").textContent =
    n >= 5 ? `Pattern analysis active${badge}` : n >= 2 ? `${n} exchanges${badge}` : "Listening carefully";
}

// ── INSIGHTS ──────────────────────────────────────────────────────────────────
async function loadInsights() {
  const empty = document.getElementById("ins-empty");
  const content = document.getElementById("ins-content");
  if (!S.sessionId) { empty.style.display = "flex"; return; }
  try {
    const d = await get(`/api/insights/${S.sessionId}`);
    if (d.empty) { empty.style.display = "flex"; content.style.display = "none"; return; }
    empty.style.display = "none"; content.style.display = "flex";
    renderInsights(d, content);
  } catch { empty.style.display = "flex"; }
}

function renderInsights(d, el) {
  const s = d.stats || {}, trend = d.trend_data || [], ems = d.emotions || [], ths = d.themes || [];
  const mc = d.mood_comparison || {}, ki = d.key_insights || [], recs = d.recommendations || [];
  const dd = d.diary_deep;

  el.innerHTML = `
    <div class="insbanner">
      <div class="insbanner-t">Your emotional landscape</div>
      <p>${d.summary || "Keep chatting and writing."}</p>
    </div>
    <div class="ins4">
      <div class="iscard"><div class="isval" style="color:var(--grn)">${s.positive_pct ?? 0}%</div><div class="islbl">Positive moments</div></div>
      <div class="iscard"><div class="isval" style="color:var(--acc)">${s.avg_mood ?? "?"}</div><div class="islbl">Avg mood /5</div></div>
      <div class="iscard"><div class="isval" style="color:var(--amb)">${s.total_chat ?? 0}</div><div class="islbl">Chat messages</div></div>
      <div class="iscard"><div class="isval" style="color:var(--teal)">${s.total_diary ?? 0}</div><div class="islbl">Diary entries</div></div>
    </div>
    <div class="ins-row two">
      <div class="ic">
        <div class="ic-t">Mood trajectory</div>
        <div class="ic-s">All entries — <span style="color:#6C63FF">■</span> chat &nbsp; <span style="color:#22D4EE">■</span> diary</div>
        <div style="position:relative;height:130px"><canvas id="lc"></canvas></div>
      </div>
      <div class="ic">
        <div class="ic-t">Emotion split</div>
        <div class="ic-s">From your words</div>
        <div class="drow" style="margin-top:10px">
          <div style="position:relative;width:88px;height:88px;flex-shrink:0"><canvas id="dc"></canvas></div>
          <div class="dleg" id="dleg"></div>
        </div>
      </div>
    </div>
<!---   <div class="ic">
      <div class="ic-t">Chat vs Diary mood</div>
      <div class="ic-s">How your emotional tone differs across sources</div>
      <div class="cmp-row">
        <div class="cmp-box"><div class="cmp-lbl">Chat mood</div><div class="cmp-val" style="color:var(--acc)">${mc.chat_avg != null ? mc.chat_avg.toFixed(2) : "N/A"}</div></div>
        <div class="cmp-box"><div class="cmp-lbl">Diary mood</div><div class="cmp-val" style="color:var(--teal)">${mc.diary_avg != null ? mc.diary_avg.toFixed(2) : "N/A"}</div></div>
      </div>
      <div class="cmp-note">${esc(mc.note || "Add both chat and diary entries to see comparison.")}</div>
    </div>-->
    
    <div class="ic">
      <div class="ic-t">Recurring themes</div>
      <div class="ic-s">Topics across all entries — diary weighted 2x</div>
      <div class="tbars" id="tbars"></div>
    </div>
    ${dd ? renderDiaryDeep(dd) : ""}
    ${ki.length ? `<div class="ic"><div class="ic-t">Key insights</div><div class="ic-s">ML-generated observations</div><div class="icard-list" id="icards"></div></div>` : ""}
    <div class="ic">
      <div class="ic-t">Personalised recommendations</div>
      <div class="ic-s">Based on your emotional patterns</div>
      <div class="rec-list" id="rrlist"></div>
    </div>
    <div class="wsum"><div class="wsul">Summary</div><p>${d.summary || ""}</p></div>
  `;

  // Line chart
  const lctx = document.getElementById("lc");
  if (lctx && trend.length) {
    if (lChart) { lChart.destroy(); lChart = null; }
    lChart = new Chart(lctx, {
      type: "line",
      data: { labels: trend.map(t => t.label), datasets: [{
        data: trend.map(t => t.score),
        borderColor: "#6C63FF", backgroundColor: "rgba(108,99,255,.08)",
        borderWidth: 2,
        pointBackgroundColor: trend.map(t => t.source === "diary" ? "#22D4EE" : "#6C63FF"),
        pointRadius: 5, tension: .45, fill: true
      }]},
      options: { responsive:true, maintainAspectRatio:false,
        plugins:{ legend:{display:false}, tooltip:{ callbacks:{ label: ctx => { const t = trend[ctx.dataIndex]; return `${t.emotion} (${t.source}) — ${t.sentiment}`; } } } },
        scales:{ y:{min:1,max:5,ticks:{stepSize:1,font:{size:10},color:"#44445A"},grid:{color:"rgba(255,255,255,.03)"},border:{display:false}}, x:{ticks:{font:{size:10},color:"#44445A"},grid:{display:false},border:{display:false}} } }
    });
  }

  // Donut
  const top5 = ems.slice(0,5);
  const dctx = document.getElementById("dc");
  if (dctx && top5.length) {
    if (dChart) { dChart.destroy(); dChart = null; }
    dChart = new Chart(dctx, {
      type:"doughnut", data:{labels:top5.map(e=>e[0]),datasets:[{data:top5.map(e=>e[1]),backgroundColor:PAL,borderWidth:0,hoverOffset:3}]},
      options:{responsive:true,maintainAspectRatio:false,plugins:{legend:{display:false}},cutout:"72%"}
    });
    const total = top5.reduce((a,e)=>a+e[1],0);
    const leg = document.getElementById("dleg");
    if (leg) leg.innerHTML = top5.map((e,i) => `<div class="dl"><div class="dlsq" style="background:${PAL[i]}"></div>${e[0]}<span class="dlpct">${Math.round(e[1]/total*100)}%</span></div>`).join("");
  }

  // Themes
  const tbars = document.getElementById("tbars");
  if (tbars) {
    if (!ths.length) { tbars.innerHTML = `<p style="font-size:12px;color:var(--t2)">Keep chatting and writing — themes emerge from your words.</p>`; }
    else {
      const max = ths[0][1];
      tbars.innerHTML = ths.slice(0,7).map((t,i) => `<div class="tbar"><div class="tbarl"><span>${t[0]}</span><span>${t[1]}×</span></div><div class="tbartrack"><div class="tbarfill" style="width:${Math.round(t[1]/max*100)}%;background:${PAL[i%PAL.length]}"></div></div></div>`).join("");
    }
  }

  // Key insights
  const icards = document.getElementById("icards");
  if (icards && ki.length) icards.innerHTML = ki.map(ic => `<div class="icard2"><div class="icard2-ico">${ic.icon}</div><div><div class="icard2-name">${esc(ic.title)}</div><div class="icard2-text">${esc(ic.text)}</div></div></div>`).join("");

  // Recs
  const rrlist = document.getElementById("rrlist");
  if (rrlist) rrlist.innerHTML = recs.map(r => `<div class="rec"><div class="rec-ico">${r.icon}</div><div><div class="rec-name">${esc(r.title)}</div><div class="rec-body">${esc(r.body)}</div></div></div>`).join("");
}

function renderDiaryDeep(dd) {
  const trendColor = dd.trend === "improving" ? "var(--grn)" : dd.trend === "declining" ? "var(--red)" : "var(--amb)";
  const trendLabel = {improving:"↑ Improving",declining:"↓ Declining",stable:"→ Stable"}[dd.trend] || "→ Stable";
  const phrases = dd.recurring_phrases?.length ? `<div style="margin-top:8px;font-size:11px;color:var(--t1)">Recurring phrases:</div><div class="phrase-chips">${dd.recurring_phrases.map(p=>`<span class="pchip">${esc(p)}</span>`).join("")}</div>` : "";
  return `<div class="ic">
    <div class="ic-t">&#128221; Diary deep analysis</div>
    <div class="ic-s">${dd.entry_count} entries — ML weighted 2× in all metrics</div>
    <div class="dd-stat"><span class="dd-k">Entries analysed</span><span class="dd-v">${dd.entry_count}</span></div>
    <div class="dd-stat"><span class="dd-k">Average diary mood</span><span class="dd-v">${dd.avg_mood}/5</span></div>
    <div class="dd-stat"><span class="dd-k">Positive entries</span><span class="dd-v">${dd.positive_pct}%</span></div>
    <div class="dd-stat"><span class="dd-k">Dominant emotion</span><span class="dd-v">${dd.dominant_emotion}</span></div>
    <div class="dd-stat"><span class="dd-k">Avg words per entry</span><span class="dd-v">${dd.avg_words_per_entry}</span></div>
    <div class="dd-stat"><span class="dd-k">Emotional trajectory</span><span class="dd-v" style="color:${trendColor}">${trendLabel}</span></div>
    ${phrases}
  </div>`;
}

// ── DIARY ─────────────────────────────────────────────────────────────────────
function openDiary() { document.getElementById("dform").classList.add("open"); document.getElementById("d-body").focus(); }
function closeDiary() {
  document.getElementById("dform").classList.remove("open");
  document.getElementById("d-title").value = ""; document.getElementById("d-body").value = "";
  const a = document.getElementById("danalysis"); a.style.display = "none"; a.innerHTML = "";
}

async function saveDiary() {
  const title = document.getElementById("d-title").value.trim();
  const body = document.getElementById("d-body").value.trim();
  if (!body) return;
  const btn = document.getElementById("dsave-btn"); btn.textContent = "Analysing..."; btn.disabled = true;
  if (!S.sessionId) await _createGuestSession();
  try {
    const r = await post("/api/diary", { sessionId: S.sessionId, title: title || "Entry", body });
    const a = r.analysis || {};
    const aEl = document.getElementById("danalysis"); aEl.style.display = "block";
    const sc = a.sentiment?.label === "positive" ? "#3DFFA0" : a.sentiment?.label === "negative" ? "#FF6B8A" : "#FFB347";
    aEl.innerHTML = `<div class="da-title">ML Analysis Complete</div>
      <div class="da-tags">
        <span class="da-tag" style="background:rgba(108,99,255,.15);color:#6C63FF">Emotion: ${a.emotion || "?"}</span>
        <span class="da-tag" style="background:rgba(255,255,255,.05);color:${sc}">Sentiment: ${a.sentiment?.label || "?"}</span>
        <span class="da-tag" style="background:rgba(255,255,255,.04);color:var(--t1)">Mood: ${a.sentiment?.rating || "?"}/5</span>
        ${(a.themes||[]).map(t=>`<span class="da-tag" style="background:rgba(34,212,238,.1);color:#22D4EE">${esc(t)}</span>`).join("")}
      </div>
      ${a.exercise ? `<div class="da-note">${a.exercise.icon} Suggested: <strong>${a.exercise.name}</strong> — ${esc(a.exercise.reason)}</div>` : ""}`;
    diaryEntries.unshift({ title: title || "Entry", body, analysis: a, date: new Date().toLocaleDateString("en-GB",{day:"numeric",month:"long",year:"numeric"}) });
    renderDiaryList();
    if (a.exercise) S.lastExercise = a.exercise;
    updateDiaryBanner();
  } catch {
    document.getElementById("danalysis").style.display = "block";
    document.getElementById("danalysis").innerHTML = `<div style="color:var(--red);font-size:12px">Could not save — ensure Flask server is running on port 5000.</div>`;
  }
  btn.textContent = "Save and Analyse"; btn.disabled = false;
}

function renderDiaryList() {
  const el = document.getElementById("dlist"); if (!el) return;
  if (!diaryEntries.length) { el.innerHTML = `<div class="empty-state" style="padding:36px"><div class="es-icon">&#128221;</div><div class="es-title">No entries yet</div><div class="es-body">Your first entry unlocks diary-specific ML insights.</div></div>`; return; }
  el.innerHTML = diaryEntries.map(e => {
    const a = e.analysis || {};
    const sc = a.sentiment?.label === "positive" ? "#3DFFA0" : a.sentiment?.label === "negative" ? "#FF6B8A" : "#FFB347";
    return `<div class="dentry">
      <h4>${esc(e.title)}</h4><p>${esc(e.body)}</p>
      <div class="dentry-meta">
        <span class="dentry-date">${e.date}</span>
        <div class="dentry-tags">
          ${a.emotion ? `<span class="dtag" style="background:var(--acca);color:var(--acc)">${a.emotion}</span>` : ""}
          ${a.sentiment ? `<span class="dtag" style="background:rgba(255,255,255,.05);color:${sc}">${a.sentiment.label}</span>` : ""}
          ${a.sentiment ? `<span class="dtag" style="background:var(--bg3);color:var(--t1)">${a.sentiment.rating}/5</span>` : ""}
        </div>
      </div>
    </div>`;
  }).join("");
}

async function updateDiaryBanner() {
  const banner = document.getElementById("diary-banner");
  if (!banner || !S.sessionId || diaryEntries.length < 2) return;
  try {
    const dd = await get(`/api/diary-analysis/${S.sessionId}`);
    if (dd.empty) return;
    const trend = {improving:"improving ↑",declining:"declining ↓",stable:"stable →"}[dd.trend] || "stable";
    banner.style.display = "block";
    banner.innerHTML = `<strong>Diary ML summary:</strong> ${dd.entry_count} entries analysed. Dominant emotion: <strong>${dd.dominant_emotion}</strong>. Trajectory: <strong>${trend}</strong>. Avg ${dd.avg_words_per_entry} words/entry.${dd.recurring_phrases?.length ? ` Recurring: ${dd.recurring_phrases.slice(0,3).map(p=>`"${esc(p)}"`).join(", ")}.` : ""}`;
  } catch {}
}

function openDiaryFromTools() { showPanel("diary"); openDiary(); }

// ── TOOLS SUGGESTION ──────────────────────────────────────────────────────────
function updateToolSuggestion() {
  const el = document.getElementById("tool-suggest"); if (!el) return;
  if (!S.lastExercise) { el.style.display = "none"; return; }
  const ex = S.lastExercise;
  const mt = ex.type === "journal" ? "gratitude" : ex.type;
  el.style.display = "block";
  el.innerHTML = `<div class="ts-t">ML-recommended for your current state</div><div class="ts-b">${ex.icon} <strong>${esc(ex.name)}</strong> — ${esc(ex.reason)}. <a href="#" onclick="openMod('${mt}');return false;" style="color:var(--grn)">Open now</a></div>`;
}

// ── MODALS ────────────────────────────────────────────────────────────────────
function openMod(name) {
  const init = { breathing:resetBreath, "478":reset478, grounding:resetGround, pmr:initPMR, pomodoro:initPomodoro, bodyscan:initBodyScan, affirmations:loadAff };
  if (init[name]) init[name]();
  document.getElementById("mod-" + name)?.classList.add("open");
}
function closeMod(name, e) {
  if (e && e.target !== document.getElementById("mod-" + name)) return;
  document.getElementById("mod-" + name)?.classList.remove("open");
  if (name === "breathing") stopBreath();
  if (name === "478") stop478();
  if (name === "pomodoro") pomReset();
}

// ── BOX BREATHING ─────────────────────────────────────────────────────────────
let bTimer = null, brCycle = 0;
function resetBreath() {
  stopBreath(); brCycle = 0;
  document.getElementById("brphlbl").textContent = "Find a comfortable position. Press begin when ready.";
  document.getElementById("brph").textContent = "Inhale through your nose";
  document.getElementById("brcnt").textContent = "4";
  document.getElementById("brinn").style.transform = "scale(1)";
  document.getElementById("brbtn").style.display = "flex";
  const cycles = document.getElementById("brcycles");
  if (cycles) cycles.innerHTML = [0,1,2,3].map(i=>`<div class="bc" id="bc${i}"></div>`).join("");
}
function stopBreath() { if (bTimer) { clearInterval(bTimer); bTimer = null; } }
function startBreath() {
  document.getElementById("brbtn").style.display = "none";
  const phases = [
    {lbl:"Breathe in...",inst:"Inhale slowly and deeply through your nose",dur:4,scale:1.55},
    {lbl:"Hold...",inst:"Hold — feel the fullness",dur:4,scale:1.55},
    {lbl:"Breathe out...",inst:"Exhale slowly through your mouth",dur:4,scale:1},
    {lbl:"Hold...",inst:"Hold — notice the calm",dur:4,scale:1},
  ];
  let pi = 0, cnt = phases[0].dur;
  function tick() {
    const p = phases[pi];
    document.getElementById("brphlbl").textContent = p.lbl;
    document.getElementById("brph").textContent = p.inst;
    document.getElementById("brcnt").textContent = cnt;
    const inn = document.getElementById("brinn");
    if (cnt === p.dur) { inn.style.transition = `transform ${p.dur * 0.88}s ease`; inn.style.transform = `scale(${p.scale})`; }
    cnt--;
    if (cnt < 0) {
      pi = (pi + 1) % phases.length;
      cnt = phases[pi].dur;
      if (pi === 0) {
        brCycle++;
        const bc = document.getElementById("bc" + (brCycle - 1));
        if (bc) bc.classList.add("done");
        if (brCycle >= 4) { stopBreath(); document.getElementById("brphlbl").textContent = "Complete. Well done."; }
      }
    }
  }
  tick(); bTimer = setInterval(tick, 1000);
}

// ── 4-7-8 BREATHING ───────────────────────────────────────────────────────────
let b478Timer = null;
function reset478() {
  stop478();
  document.getElementById("b478lbl").textContent = "A powerful reset for deep anxiety and sleep.";
  document.getElementById("brph478").textContent = "Inhale through your nose";
  document.getElementById("brcnt478").textContent = "4";
  document.getElementById("brinn478").style.transform = "scale(1)";
  document.getElementById("b478btn").style.display = "flex";
}
function stop478() { if (b478Timer) { clearInterval(b478Timer); b478Timer = null; } }
function start478() {
  document.getElementById("b478btn").style.display = "none";
  const phases = [
    {lbl:"Inhale...",inst:"Breathe in through your nose",dur:4,scale:1.5},
    {lbl:"Hold...",inst:"Hold your breath completely",dur:7,scale:1.5},
    {lbl:"Exhale...",inst:"Breathe out through your mouth with a whoosh",dur:8,scale:1},
  ];
  let pi = 0, cnt = phases[0].dur;
  function tick() {
    const p = phases[pi];
    document.getElementById("b478lbl").textContent = p.lbl;
    document.getElementById("brph478").textContent = p.inst;
    document.getElementById("brcnt478").textContent = cnt;
    const inn = document.getElementById("brinn478");
    if (cnt === p.dur) { inn.style.transition = `transform ${p.dur * 0.88}s ease`; inn.style.transform = `scale(${p.scale})`; }
    cnt--;
    if (cnt < 0) { pi = (pi + 1) % phases.length; cnt = phases[pi].dur; }
  }
  tick(); b478Timer = setInterval(tick, 1000);
}

// ── GROUNDING ─────────────────────────────────────────────────────────────────
let gStep = 0;
function resetGround() {
  gStep = 0;
  for (let i = 0; i < 5; i++) { const el = document.getElementById("gs" + i); if (el) el.classList.toggle("on", i === 0); }
  const btn = document.getElementById("gbtn"); if (btn) btn.textContent = "Next step";
}
function gNext() {
  document.getElementById("gs" + gStep)?.classList.remove("on");
  gStep++;
  if (gStep >= 5) { closeMod("grounding"); resetGround(); return; }
  document.getElementById("gs" + gStep)?.classList.add("on");
  if (gStep === 4) document.getElementById("gbtn").textContent = "Complete ✓";
}

// ── PMR ───────────────────────────────────────────────────────────────────────
const PMR_STEPS = [
  {muscle:"Hands & forearms",inst:"Make tight fists. Hold for 5 seconds.",tip:"Feel the tension in your fingers and forearms."},
  {muscle:"Biceps",inst:"Flex your biceps hard, curl your arms up. Hold.",tip:"Notice the difference between tension and relaxation."},
  {muscle:"Shoulders",inst:"Shrug your shoulders up to your ears. Hold tight.",tip:"Feel them pressed against your neck."},
  {muscle:"Forehead",inst:"Raise your eyebrows as high as possible. Hold.",tip:"Feel the wrinkling across your forehead."},
  {muscle:"Eyes & nose",inst:"Squeeze eyes shut and scrunch your nose. Hold.",tip:"Notice the tension around your eyes."},
  {muscle:"Jaw",inst:"Bite down gently and pull back the corners of your mouth. Hold.",tip:"Feel your jaw muscles working."},
  {muscle:"Chest",inst:"Breathe in deeply and hold it. Tighten your chest.",tip:"Feel the pressure build as you hold."},
  {muscle:"Abdomen",inst:"Tighten your stomach muscles, pull in your belly. Hold.",tip:"As if bracing for a gentle punch."},
  {muscle:"Legs & feet",inst:"Straighten your legs, curl your toes downward. Hold.",tip:"Feel the tension running from thighs to toes."},
];
let pmrStep = -1, pmrPhase = "tension", pmrTimer2 = null;
function initPMR() {
  pmrStep = -1; pmrPhase = "tension";
  if (pmrTimer2) { clearInterval(pmrTimer2); pmrTimer2 = null; }
  document.getElementById("pmr-fill").style.width = "0%";
  document.getElementById("pmr-step-wrap").innerHTML = `<div style="text-align:center;padding:20px 0;color:var(--t1);font-size:13px">Ready to begin. Each muscle group: tense 5s, release 10s.</div>`;
  document.getElementById("pmr-btn").textContent = "Start";
}
function pmrNext() {
  if (pmrTimer2) { clearInterval(pmrTimer2); pmrTimer2 = null; }
  pmrStep++;
  if (pmrStep >= PMR_STEPS.length) {
    document.getElementById("pmr-step-wrap").innerHTML = `<div style="text-align:center;padding:20px 0;color:var(--grn);font-size:14px;font-weight:500">Complete. Your body should feel noticeably more relaxed.</div>`;
    document.getElementById("pmr-fill").style.width = "100%";
    document.getElementById("pmr-btn").textContent = "Done";
    document.getElementById("pmr-btn").onclick = () => closeMod("pmr");
    return;
  }
  const step = PMR_STEPS[pmrStep];
  document.getElementById("pmr-fill").style.width = `${Math.round((pmrStep / PMR_STEPS.length) * 100)}%`;
  pmrPhase = "tension"; renderPMR(step, 5);
}
function renderPMR(step, countdown) {
  const isTension = pmrPhase === "tension";
  document.getElementById("pmr-step-wrap").innerHTML = `
    <div class="pmr-step on">
      <div class="pmr-muscle">${step.muscle}</div>
      <div class="pmr-inst">${isTension ? step.inst : "Now completely release. Let all tension go."}</div>
      <div class="pmr-tip">${isTension ? step.tip : "Feel the warmth and heaviness of relaxed muscles."}</div>
    </div>
    <div style="text-align:center;font-family:var(--serif);font-size:36px;color:${isTension?"var(--red)":"var(--grn)"};margin:14px 0">${countdown}s</div>
    <div style="text-align:center;font-size:11px;color:var(--t1);text-transform:uppercase;letter-spacing:.4px">${isTension ? "TENSE" : "RELEASE"}</div>
  `;
  let cnt = countdown;
  document.getElementById("pmr-btn").textContent = "Skip";
  pmrTimer2 = setInterval(() => {
    cnt--;
    const el = document.querySelector("#pmr-step-wrap [style*='font-size:36px']");
    if (el) el.textContent = cnt + "s";
    if (cnt <= 0) {
      clearInterval(pmrTimer2); pmrTimer2 = null;
      if (pmrPhase === "tension") {
        pmrPhase = "release"; renderPMR(step, 10);
      } else {
        pmrNext();
      }
    }
  }, 1000);
}

// ── POMODORO ──────────────────────────────────────────────────────────────────
let pomTimer = null, pomSeconds = 25*60, pomRunning = false, pomSessions = 0, pomIsBreak = false;
function initPomodoro() { pomReset(); }
function pomToggle() {
  if (pomRunning) {
    clearInterval(pomTimer); pomTimer = null; pomRunning = false;
    document.getElementById("pom-btn").textContent = "Resume";
  } else {
    pomRunning = true;
    document.getElementById("pom-btn").textContent = "Pause";
    pomTimer = setInterval(() => {
      pomSeconds--;
      if (pomSeconds < 0) {
        clearInterval(pomTimer); pomTimer = null; pomRunning = false;
        if (!pomIsBreak) {
          pomSessions++; pomIsBreak = true; pomSeconds = 5 * 60;
          document.getElementById("pom-label").textContent = "Break time!";
        } else {
          pomIsBreak = false; pomSeconds = 25 * 60;
          document.getElementById("pom-label").textContent = "Focus session";
        }
        renderPomCount(); pomToggle();
        return;
      }
      const m = Math.floor(pomSeconds / 60), s = pomSeconds % 60;
      document.getElementById("pom-time").textContent = `${String(m).padStart(2,"0")}:${String(s).padStart(2,"0")}`;
    }, 1000);
  }
}
function pomReset() {
  if (pomTimer) { clearInterval(pomTimer); pomTimer = null; }
  pomRunning = false; pomSeconds = 25*60; pomSessions = 0; pomIsBreak = false;
  document.getElementById("pom-time").textContent = "25:00";
  document.getElementById("pom-label").textContent = "Focus session";
  document.getElementById("pom-btn").textContent = "Start";
  renderPomCount();
}
function renderPomCount() {
  const el = document.getElementById("pom-count");
  if (el) el.innerHTML = [0,1,2,3].map(i=>`<div class="pom-dot${i<pomSessions?" done":""}"></div>`).join("");
}

// ── BODY SCAN ─────────────────────────────────────────────────────────────────
const BODY_AREAS = [
  {name:"Head & scalp",inst:"Bring awareness to the top of your head. Notice any tension, tingling, or sensation. Just observe without changing anything."},
  {name:"Face & jaw",inst:"Notice your forehead, eyes, cheeks, jaw. Is there tightness anywhere? Let your jaw drop slightly if it feels held."},
  {name:"Neck & shoulders",inst:"Scan your neck and shoulder area — one of the most common places we hold stress. Just notice what's there."},
  {name:"Chest & upper back",inst:"Bring attention to your chest. Notice the rise and fall with each breath. Is there heaviness or tightness?"},
  {name:"Arms & hands",inst:"Move awareness down both arms to your hands. Notice temperature, weight, any tingling."},
  {name:"Abdomen",inst:"The belly. Notice if it's held tight or soft. Breathe into it gently and observe any sensations."},
  {name:"Lower back & hips",inst:"The lower back and hips — another area where stress and emotion often settle. Just notice."},
  {name:"Legs & feet",inst:"Down through both legs, calves, to your feet and toes. Notice contact with the floor or chair."},
];
let bsStep = -1;
function initBodyScan() {
  bsStep = -1;
  document.getElementById("bodyscan-area").innerHTML = `<div style="text-align:center;padding:16px 0;color:var(--t1);font-size:13px">Sit or lie comfortably. Close your eyes if possible.<br/>Each area: 20–30 seconds of gentle awareness.</div>`;
  document.getElementById("bs-btn").textContent = "Begin";
}
function bsNext() {
  bsStep++;
  if (bsStep >= BODY_AREAS.length) {
    document.getElementById("bodyscan-area").innerHTML = `<div style="text-align:center;padding:16px 0;color:var(--grn);font-size:13px">Complete. Take a moment before moving.</div>`;
    document.getElementById("bs-btn").textContent = "Close";
    document.getElementById("bs-btn").onclick = () => closeMod("bodyscan");
    return;
  }
  const area = BODY_AREAS[bsStep];
  document.getElementById("bodyscan-area").innerHTML = `<div class="body-area"><div class="body-area-name">${area.name}</div><div class="body-area-inst">${area.inst}</div></div><div style="text-align:center;font-size:12px;color:var(--t2);margin-top:8px">${bsStep+1} of ${BODY_AREAS.length}</div>`;
  document.getElementById("bs-btn").textContent = bsStep < BODY_AREAS.length - 1 ? "Next area" : "Complete";
}

// ── GRATITUDE ─────────────────────────────────────────────────────────────────
async function saveGrat() {
  const vals = ["g1","g2","g3"].map(id => document.getElementById(id)?.value.trim()).filter(Boolean);
  if (!vals.length) return;
  const title = `Gratitude ${new Date().toLocaleDateString("en-GB",{day:"numeric",month:"long"})}`;
  const body = vals.map((v,i) => `${i+1}. ${v}`).join("\n");
  if (!S.sessionId) await _createGuestSession();
  try {
    const r = await post("/api/diary", { sessionId: S.sessionId, title, body });
    diaryEntries.unshift({ title, body, analysis: r.analysis || {}, date: new Date().toLocaleDateString("en-GB",{day:"numeric",month:"long",year:"numeric"}) });
    renderDiaryList();
  } catch {
    diaryEntries.unshift({ title, body, analysis: {}, date: new Date().toLocaleDateString("en-GB",{day:"numeric",month:"long",year:"numeric"}) });
    renderDiaryList();
  }
  ["g1","g2","g3"].forEach(id => { const el = document.getElementById(id); if (el) el.value = ""; });
  closeMod("gratitude");
}

// ── AFFIRMATIONS ──────────────────────────────────────────────────────────────
let affIdx = 0;
const AFFS = [
  ["My feelings are valid, even when I don't understand them.","I am doing the best I can with what I have right now.","It's okay to ask for help. That takes courage, not weakness."],
  ["I don't need everything figured out today.","My worth is not determined by my productivity.","This moment is hard. Hard moments pass."],
  ["I have navigated difficult situations before and got through them.","I am allowed to take up space and have needs.","Small steps are still steps forward."],
  ["Struggling does not make me broken — it makes me human.","I am not responsible for things outside my control.","Asking for what I need is an act of self-respect."],
  ["My past does not define who I am becoming.","Rest is productive. My body and mind need recovery.","One breath at a time. One moment at a time."],
];
function loadAff() {
  const el = document.getElementById("afflist"); if (!el) return;
  el.innerHTML = AFFS[affIdx % AFFS.length].map(a => `<div class="affitem">${esc(a)}</div>`).join("");
}
function nextAff() { affIdx++; loadAff(); }

// ── COGNITIVE REFRAMING ───────────────────────────────────────────────────────
async function saveCognitive() {
  const thought = document.getElementById("cog-t")?.value.trim();
  const forIt = document.getElementById("cog-for")?.value.trim();
  const against = document.getElementById("cog-against")?.value.trim();
  const balanced = document.getElementById("cog-balanced")?.value.trim();
  if (!thought) return;
  const body = `Thought: ${thought}\n\nEvidence supporting it:\n${forIt || "(none listed)"}\n\nEvidence against it:\n${against || "(none listed)"}\n\nMore balanced perspective:\n${balanced || "(not yet written)"}`;
  if (!S.sessionId) await _createGuestSession();
  try {
    const r = await post("/api/diary", { sessionId: S.sessionId, title: "Cognitive reframe", body });
    diaryEntries.unshift({ title: "Cognitive reframe", body, analysis: r.analysis || {}, date: new Date().toLocaleDateString("en-GB",{day:"numeric",month:"long",year:"numeric"}) });
    renderDiaryList();
  } catch {}
  ["cog-t","cog-for","cog-against","cog-balanced"].forEach(id => { const el = document.getElementById(id); if (el) el.value = ""; });
  closeMod("cognitive");
}
