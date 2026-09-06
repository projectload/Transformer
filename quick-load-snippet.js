/* ============================================================================
   نظرة سريعة لأحمال المحول والفيدرات (Quick Load Popup)
   ملف نقل جاهز — انسخ الأجزاء الأربعة إلى مشروعك الآخر.

   ── المتطلبات (يجب أن تكون موجودة في المشروع الهدف) ──────────────────────────
     records            : مصفوفة المحولات، كل عنصر { uid, id, station, capacity, hvFeeder }
     loadings           : كائن القراءات  loadings[uid] = { _round, _allRounds:{n:{feeders,volt,pf,voltSavedAt}} }
                          كل feeder = { num, name(مقاس الكيبل), iL1, iL2, iL3, iN, savedAt }
     lang               : 'ar' أو 'en'
     hasData(f)         : هل للفيدر قراءة؟
     cableStatus(f)     : يرجع { ampacity, maxI, pct, level } حسب مقاس الكيبل
     formatHvFeeder(v)  : اسم فيدر الجهد العالي (اختياري — احذف السطر إن لم يوجد)
     formatDateTimeShort(iso) : تنسيق التاريخ (اختياري)
   إن كان جهد الشبكة عندك غير 415V غيّره في qlRounds.
   ============================================================================ */


/* ───────────────────────── الجزء 1: الكود الأساسي ─────────────────────────
   ضعه داخل نفس <script> الرئيسي في صفحتك (نطاق عام حتى يناديه الـ iframe). */

// ─── نظرة سريعة: حمل المحول + أحمال الفيدرات في نافذة واحدة بدون تمرير ───
var _qlUid = null, _qlRound = null, _qlFocus = null;
function qlColor(p) { return p >= 100 ? '#dc2626' : p >= 80 ? '#ea580c' : p >= 60 ? '#f59e0b' : '#16a34a'; }
function qlRounds(uid) {
  const ld = loadings[uid];
  if (!ld) return [];
  const SQRT3 = Math.sqrt(3);
  const rec = records.find(r => r.uid === uid);
  const capKVA = rec ? Number(rec.capacity) : 0;
  const rated = capKVA > 0 ? (capKVA * 1000) / (SQRT3 * 415) : 0;
  const all = (ld._allRounds && Object.keys(ld._allRounds).length)
    ? ld._allRounds
    : { [ld._round || 1]: { volt: ld.volt||{}, pf: ld.pf, feeders: ld.feeders||[], voltSavedAt: ld.voltSavedAt } };
  return Object.keys(all).map(Number).sort((a,b)=>a-b).map(num => {
    const rd = all[num] || {};
    const fds = (rd.feeders || []).filter(hasData).sort((a,b)=>(a.num||0)-(b.num||0));
    const totR = fds.reduce((s,f)=>s+(parseFloat(f.iL1)||0),0);
    const totY = fds.reduce((s,f)=>s+(parseFloat(f.iL2)||0),0);
    const totB = fds.reduce((s,f)=>s+(parseFloat(f.iL3)||0),0);
    const maxI = Math.max(totR, totY, totB);
    const pct  = rated > 0 ? (maxI / rated) * 100 : 0;
    const at   = fds.map(f=>f.savedAt).filter(Boolean).sort().pop() || rd.voltSavedAt || null;
    return { num, feeders: fds, totR, totY, totB, maxI, pct, rated, capKVA, savedAt: at };
  }).filter(r => r.feeders.length);
}
// focusFeeder: رقم الفيدر القادم من تنبيه الكيبل (اختياري) — يفتح جولته الأعلى ويظلّله
function openQuickLoad(uid, focusFeeder) {
  _qlUid = uid;
  _qlFocus = (focusFeeder != null && focusFeeder !== '') ? Number(focusFeeder) : null;
  const rounds = qlRounds(uid);
  let best = null;
  if (_qlFocus != null) {
    // إذا جئنا من تنبيه كيبل: افتح الجولة التي فيها أعلى تحميل لهذا الفيدر
    let bp = -1;
    rounds.forEach(r => {
      const f = r.feeders.find(x => x.num === _qlFocus);
      const cs = f ? cableStatus(f) : null;
      if (cs && cs.pct > bp) { bp = cs.pct; best = r; }
    });
  }
  if (!best) rounds.forEach(r => { if (!best || r.pct > best.pct) best = r; });
  _qlRound = best ? best.num : null;
  renderQuickLoad();
}
function renderQuickLoad() {
  const uid = _qlUid, isAr = lang === 'ar';
  const rec = records.find(r => r.uid === uid);
  if (!rec) return;
  let ov = document.getElementById('quickLoadOverlay');
  if (!ov) {
    const st = document.createElement('style');
    st.textContent = `
      #quickLoadOverlay{position:fixed;inset:0;z-index:10001;background:rgba(15,23,42,0.55);display:none;align-items:center;justify-content:center;
        padding:max(0.7rem,env(safe-area-inset-top)) 0.7rem max(0.7rem,env(safe-area-inset-bottom))}
      .ql-card{background:#fff;border-radius:16px;box-shadow:0 20px 50px rgba(0,0,0,0.35);width:100%;max-width:540px;
        max-height:92vh;max-height:92svh;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:0.9rem 1rem;font-family:'Cairo',sans-serif;color:#0f172a}
      .ql-head{display:flex;align-items:flex-start;justify-content:space-between;gap:0.6rem;margin-bottom:0.7rem}
      .ql-id{font-size:1.02rem;font-weight:900;word-break:break-word}
      .ql-sub{font-size:0.76rem;color:#64748b;font-family:'Tajawal',sans-serif;line-height:1.5}
      .ql-x{flex:0 0 auto;width:36px;height:36px;border-radius:10px;border:1px solid #e2e8f0;background:#f8fafc;color:#64748b;font-size:1rem;cursor:pointer;line-height:1}
      .ql-tabs{display:flex;gap:0.35rem;flex-wrap:wrap;margin-bottom:0.7rem}
      .ql-tab{min-height:32px;padding:0.25rem 0.7rem;border-radius:8px;cursor:pointer;font-family:'Cairo',sans-serif;font-size:0.78rem;font-weight:700}
      .ql-hero{display:flex;align-items:center;gap:0.9rem;border-radius:12px;padding:0.6rem 0.9rem;margin-bottom:0.7rem}
      .ql-pct{font-size:1.7rem;font-weight:900;font-family:monospace;line-height:1;flex:0 0 auto}
      .ql-meta{font-size:0.76rem;color:#64748b;font-family:'Tajawal',sans-serif;word-break:break-word}
      .ql-ph{display:flex;gap:0.4rem;margin-bottom:0.7rem;font-family:monospace;font-size:0.8rem}
      .ql-ph span{flex:1;text-align:center;border-radius:8px;padding:0.3rem 0;font-weight:800;white-space:nowrap}
      .ql-tblwrap{overflow-x:auto;-webkit-overflow-scrolling:touch}
      .ql-tbl{width:100%;border-collapse:collapse;min-width:320px}
      .ql-tbl th{padding:0.35rem 0.25rem;text-align:center;font-size:0.7rem;font-weight:700;color:#475569;background:#f1f5f9;font-family:'Tajawal',sans-serif;white-space:nowrap}
      .ql-tbl td{padding:0.36rem 0.25rem;text-align:center;border-bottom:1px solid #eef2f6;font-family:monospace;font-size:0.84rem;white-space:nowrap}
      .ql-time{margin-top:0.5rem;font-size:0.72rem;color:#94a3b8;text-align:center;font-family:'Tajawal',sans-serif}
      .ql-acts{display:flex;gap:0.4rem;justify-content:center;margin-top:0.8rem;flex-wrap:wrap}
      .ql-btn{min-height:36px;padding:0.35rem 0.8rem;border-radius:8px;border:1px solid #cbd5e1;background:#fff;color:#475569;font-family:'Cairo',sans-serif;font-size:0.78rem;font-weight:700;cursor:pointer}
      @media (max-width:430px){
        #quickLoadOverlay{padding:max(0.4rem,env(safe-area-inset-top)) 0.4rem max(0.4rem,env(safe-area-inset-bottom))}
        .ql-card{padding:0.75rem 0.6rem;border-radius:14px;max-height:95vh;max-height:95svh}
        .ql-id{font-size:0.95rem}
        .ql-hero{gap:0.6rem;padding:0.5rem 0.6rem}
        .ql-pct{font-size:1.45rem}
        .ql-ph{font-size:0.75rem}
        .ql-tbl td{font-size:0.78rem;padding:0.32rem 0.16rem}
        .ql-tbl th{font-size:0.65rem;padding:0.3rem 0.16rem}
      }`;
    document.head.appendChild(st);
    ov = document.createElement('div');
    ov.id = 'quickLoadOverlay';
    ov.addEventListener('click', e => { if (e.target === ov) closeQuickLoad(); });
    document.body.appendChild(ov);
  }
  ov.dir = isAr ? 'rtl' : 'ltr';
  const rounds = qlRounds(uid);
  const cur = rounds.find(r => r.num === _qlRound) || rounds[0];
  const hv = formatHvFeeder(rec.hvFeeder);
  let body;
  if (!cur) {
    body = `<div style="padding:1.6rem;text-align:center;color:#94a3b8;font-family:'Tajawal',sans-serif">${isAr?'لا توجد قراءات محفوظة':'No saved readings'}</div>`;
  } else {
    const c = qlColor(cur.pct);
    const kva = cur.capKVA ? (cur.capKVA * cur.pct / 100) : 0;
    const tabs = rounds.length > 1 ? `<div class="ql-tabs">` + rounds.map(r => {
      const on = r.num === cur.num, rc = qlColor(r.pct);
      return `<button class="ql-tab" onclick="_qlRound=${r.num};renderQuickLoad()" style="border:1px solid ${on?rc:'#cbd5e1'};background:${on?rc:'#fff'};color:${on?'#fff':'#64748b'}">${isAr?'ق':'R'}${r.num} · ${Math.round(r.pct)}%</button>`;
    }).join('') + `</div>` : '';
    const rows = cur.feeders.map(f => {
      const cs = cableStatus(f);
      const fc = cs ? qlColor(cs.pct) : '#94a3b8';
      // تظليل خفيف: الفيدر القادم من التنبيه، أو أي كيبل محمّل 80%+
      const isFocus = _qlFocus != null && f.num === _qlFocus;
      const hot = cs && cs.pct >= 80;
      const rowS = isFocus ? `background:${fc}20` : (hot ? `background:${fc}12` : '');
      return `<tr style="${rowS}">
        <td style="color:#a78bfa;font-weight:800${isFocus?';border-inline-start:3px solid '+fc:''}">${f.num||'—'}</td>
        <td style="font-family:'Tajawal',sans-serif;color:#475569">${f.name?f.name+' mm²':'—'}</td>
        <td style="color:#dc2626">${f.iL1||'—'}</td>
        <td style="color:#ca8a04">${f.iL2||'—'}</td>
        <td style="color:#2563eb">${f.iL3||'—'}</td>
        <td style="color:#64748b">${f.iN||'—'}</td>
        <td style="color:${fc};font-weight:800">${cs?Math.round(cs.pct)+'%':'—'}</td>
      </tr>`;
    }).join('');
    body = `${tabs}
      <div class="ql-hero" style="background:${c}12;border:1px solid ${c}55">
        <div class="ql-pct" style="color:${c}">${Math.round(cur.pct)}%</div>
        <div style="flex:1 1 auto;min-width:0">
          <div style="height:7px;border-radius:4px;background:#e2e8f0;overflow:hidden;margin-bottom:0.3rem"><i style="display:block;height:100%;width:${Math.min(100,cur.pct)}%;background:${c}"></i></div>
          <div class="ql-meta">${kva.toFixed(1)} / ${cur.capKVA} KVA · ${cur.maxI.toFixed(0)} / ${cur.rated.toFixed(0)} A</div>
        </div>
      </div>
      <div class="ql-ph">
        <span style="background:#fef2f2;border:1px solid #fecaca;color:#dc2626">R ${cur.totR.toFixed(0)}</span>
        <span style="background:#fefce8;border:1px solid #fde68a;color:#ca8a04">Y ${cur.totY.toFixed(0)}</span>
        <span style="background:#eff6ff;border:1px solid #bfdbfe;color:#2563eb">B ${cur.totB.toFixed(0)}</span>
      </div>
      <div class="ql-tblwrap"><table class="ql-tbl">
        <thead><tr>
          <th>#</th><th>${isAr?'الكيبل':'Cable'}</th>
          <th style="color:#dc2626">R</th><th style="color:#ca8a04">Y</th>
          <th style="color:#2563eb">B</th><th>N</th>
          <th>${isAr?'الكيبل %':'Cable %'}</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table></div>
      ${cur.savedAt?`<div class="ql-time">🕐 ${formatDateTimeShort(cur.savedAt)}</div>`:''}`;
  }
  ov.innerHTML = `<div class="ql-card">
    <div class="ql-head">
      <div style="min-width:0">
        <div class="ql-id">Tx: ${rec.id||'—'}</div>
        <div class="ql-sub">${rec.station||'—'}${hv!=='—'?' · '+hv:''} · ${rec.capacity||'—'} KVA</div>
      </div>
      <button class="ql-x" onclick="closeQuickLoad()">✕</button>
    </div>
    ${body}
    <div class="ql-acts">
      <button class="ql-btn" onclick="qlOpenFull()">📊 ${isAr?'كل القراءات':'All readings'}</button>
      <button class="ql-btn" onclick="qlOpenReport()">📄 ${isAr?'التقرير':'Report'}</button>
    </div>
  </div>`;
  ov.style.display = 'flex';
}
function closeQuickLoad() {
  const ov = document.getElementById('quickLoadOverlay');
  if (ov) ov.style.display = 'none';
  _qlUid = null; _qlFocus = null;
}
// الزرّان السفليان — احذفهما من renderQuickLoad إن لم تكن هذه الدوال موجودة عندك
function qlOpenFull()   { const u = _qlUid; closeQuickLoad(); if (u) openLoadFromAlerts(u); }
function qlOpenReport() { const u = _qlUid; closeQuickLoad(); if (u) { _returnToAlerts = true; openReport(u); } }


/* ───────── الجزء 2: فتح نافذة القراءات الكاملة والرجوع لصفحة التنبيهات ─────────
   يعتمد على reportOverlay (طبقة الـ iframe) + openLoadModal + openAlerts.
   إن لم تكن صفحة تنبيهاتك داخل iframe، احذف هذا الجزء واستبدل qlOpenFull بما يناسبك. */

var _returnToAlerts = false;

function openLoadFromAlerts(uid) {
  const ov = document.getElementById('reportOverlay');
  if (ov) ov.style.display = 'none';
  document.body.style.overflow = '';
  _returnToAlerts = true;
  loadModalMode = 'browse';
  openLoadModal(uid, false);
}

// أضف هذا السطر داخل closeLoadModal() عندك:
//   if (_returnToAlerts) { _returnToAlerts = false; openAlerts(); }

// وداخل closeReportPage() في أوله:
//   if (_returnToAlerts) { _returnToAlerts = false; openAlerts(); return; }

// مفتاح Escape: أغلق النظرة السريعة أولاً ثم صفحة التقرير
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const ql = document.getElementById('quickLoadOverlay');
  if (ql && ql.style.display === 'flex') { closeQuickLoad(); return; }
  const ov = document.getElementById('reportOverlay');
  if (ov && ov.style.display !== 'none') closeReportPage();
});


/* ───────── الجزء 3: الربط من داخل صفحة التنبيهات (كود داخل الـ iframe) ─────────
   داخل نص الـ HTML المولَّد لصفحة التنبيهات: */

//   function goTo(uid,fd){ parent.openQuickLoad(uid, fd?+fd:null); }

/* جدول المحولات المحمّلة — رقم المحول قابل للضغط (بدون رقم فيدر): */
//   '<td class="bold"><span style="cursor:pointer;text-decoration:underline" data-uid="'+a.uid+'"'
// + ' onclick="goTo(this.dataset.uid)">(Tx:'+a.id+')</span></td>'

/* جدول الكيبلات المحمّلة — نمرّر رقم الفيدر ليُظلَّل داخل النافذة: */
//   '<td class="bold"><span style="cursor:pointer;text-decoration:underline" data-uid="'+a.uid+'"'
// + ' data-fd="'+(a.feederNum||'')+'" onclick="goTo(this.dataset.uid,this.dataset.fd)">(Tx:'+a.id+')</span></td>'

/* لا تنسَ تمرير feederNum ضمن بيانات صف الكيبل عند بناء المصفوفة:
     const CB = cables.map(a => ({ ..., feederNum: a.feederNum, ... }));            */


/* ───────── الجزء 4: تجربة سريعة بدون مشروع (اختياري) ─────────
   لتجربة النافذة لوحدها في صفحة فارغة، عرّف الحد الأدنى ثم نادِ openQuickLoad:

   const CABLE_AMPACITY = {50:187,70:229,120:312,185:394,240:455,300:509,630:705};
   function hasData(f){ return [f.iL1,f.iL2,f.iL3,f.iN].some(v => v !== '' && v !== undefined); }
   function cableStatus(f){
     const size = parseInt(f.name), amp = CABLE_AMPACITY[size];
     if (!amp) return null;
     const maxI = Math.max(parseFloat(f.iL1)||0, parseFloat(f.iL2)||0, parseFloat(f.iL3)||0);
     return { ampacity: amp, maxI, pct: maxI/amp*100, level: 'ok' };
   }
   function formatHvFeeder(v){ const n = String(v||'').replace(/[^0-9]/g,''); return n ? 'K_LN'+n : '—'; }
   function formatDateTimeShort(s){ return s ? new Date(s).toLocaleString('en-GB') : null; }
   let lang = 'ar';
   const records  = [{ uid:'u1', id:'125', station:'AL-MURTAFA', capacity:'500', hvFeeder:'2' }];
   const loadings = { u1: { _round:1, _allRounds:{ 1:{ feeders:[
     { num:5, name:'120', iL1:'386', iL2:'340', iL3:'300', iN:'40', savedAt:new Date().toISOString() },
     { num:6, name:'185', iL1:'120', iL2:'130', iL3:'110', iN:'12', savedAt:new Date().toISOString() }
   ], volt:{}, pf:'0.9', voltSavedAt:null } } } };
   openQuickLoad('u1', 5);
*/
