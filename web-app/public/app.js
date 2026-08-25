// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-PackageHomePage: https://github.com/paxx12-snapmaker-u1/spool-link
// SPDX-FileCopyrightText: Copyright (c) 2026 @paxx12

// ─── Spoolman API ────────────────────────────────────────────────────────────

class SpoolmanAPI {
  constructor(baseURL) {
    this.baseURL = normalizeURL(baseURL);
  }

  setBaseURL(url) { this.baseURL = normalizeURL(url); }

  async fetchSpools(limit = 20, offset = 0) {
    const url = new URL(`${this.baseURL}api/v1/spool`);
    url.searchParams.set('limit', limit);
    url.searchParams.set('offset', offset);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Server error: ${res.status}`);
    return res.json();
  }

  async getSpool(id) {
    const res = await fetch(`${this.baseURL}api/v1/spool/${id}`);
    if (res.status === 404) throw new Error(`Spool ${id} not found`);
    if (!res.ok) throw new Error(`Server error: ${res.status}`);
    return res.json();
  }

  async findSpoolsByCardUid(uid) {
    const url = new URL(`${this.baseURL}api/v1/spool`);
    url.searchParams.set('limit', 1000);
    url.searchParams.set('allow_archived', true);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Server error: ${res.status}`);
    const all = await res.json();
    return all.filter(spool => spoolTagUIDs(spool).includes(uid.toUpperCase()));
  }

  async updateSpoolCardUids(id, uids) {
    const res = await fetch(`${this.baseURL}api/v1/spool/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ extra: { card_uids: JSON.stringify(uids.join(',')) } }),
    });
    if (!res.ok) throw new Error(`Server error: ${res.status}`);
  }

  async ensureCardUidsFieldExists() {
    const listRes = await fetch(`${this.baseURL}api/v1/field/spool`);
    if (!listRes.ok) return;
    const fields = await listRes.json();
    if (fields.some(f => f.key === 'card_uids')) return;

    await fetch(`${this.baseURL}api/v1/field/spool/card_uids`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        key: 'card_uids',
        name: 'Card UIDs',
        entity_type: 'spool',
        field_type: 'text',
        order: 1,
        default_value: JSON.stringify(''),
      }),
    });
  }

  async getVendors() {
    const res = await fetch(`${this.baseURL}api/v1/vendor`);
    if (!res.ok) return [];
    return res.json();
  }

  async findOrCreateVendor(name) {
    const vendors = await this.getVendors();
    const existing = vendors.find(v => v.name?.toLowerCase() === name.toLowerCase());
    if (existing) return existing.id;
    const res = await fetch(`${this.baseURL}api/v1/vendor`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name }),
    });
    if (!res.ok) throw new Error(`Server error: ${res.status}`);
    const v = await res.json();
    return v.id;
  }

  async createSpoolFromInfo({ filamentName, vendorId, material, colorHex, diameter, weight, nozzleTemp, bedTemp, cardUid, subtype }) {
    const density = MATERIAL_DENSITY[material?.toUpperCase()] ?? 1.24;
    const filBody = {
      name: filamentName,
      vendor_id: vendorId ?? null,
      material: material ?? null,
      color_hex: colorHex ?? null,
      diameter: diameter ?? 1.75,
      weight: weight ?? null,
      density,
      settings_extruder_temp: nozzleTemp ?? null,
      settings_bed_temp: bedTemp ?? null,
    };
    if (subtype) filBody.extra = { variant: JSON.stringify(subtype) };
    const filRes = await fetch(`${this.baseURL}api/v1/filament`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(filBody),
    });
    if (!filRes.ok) throw new Error(`Server error: ${filRes.status}`);
    const filament = await filRes.json();

    const body = { filament_id: filament.id };
    if (cardUid) body.extra = { card_uids: JSON.stringify(cardUid) };
    const spoolRes = await fetch(`${this.baseURL}api/v1/spool`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!spoolRes.ok) throw new Error(`Server error: ${spoolRes.status}`);
    return spoolRes.json();
  }

  static async testConnection(baseURL) {
    const logs = [];
    const normalized = normalizeURL(baseURL);
    const urlStr = `${normalized}api/v1/info`;
    logs.push(`GET ${urlStr}`);
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 5000);
      const t0 = Date.now();
      const res = await fetch(urlStr, { signal: controller.signal });
      clearTimeout(timer);
      const ms = Date.now() - t0;
      logs.push(`${res.status} ${res.statusText} (${ms}ms)`);
      if (!res.ok) {
        logs.push(`✗ Server error: ${res.status}`);
        return { logs, error: `Server error: ${res.status}` };
      }
      let info;
      try { info = await res.json(); } catch { info = null; }
      if (!info?.version) {
        logs.push('✗ Response is not a Spoolman server');
        return { logs, error: 'Response is not a Spoolman server' };
      }
      let detail = `Spoolman v${info.version}`;
      if (info.db_type) detail += ` (${info.db_type})`;
      if (info.git_commit) detail += ` ${info.git_commit}`;
      logs.push(`✓ ${detail}`);

      async function ensureField(entityType, key, name) {
        const listURL = `${normalized}api/v1/field/${entityType}`;
        const createURL = `${normalized}api/v1/field/${entityType}/${key}`;
        logs.push(`GET ${listURL}`);
        try {
          const listRes = await fetch(listURL);
          if (!listRes.ok) {
            logs.push(`⚠ could not read custom fields for ${entityType}`);
            return;
          }
          const fields = await listRes.json();
          if (fields.some(f => f.key === key)) {
            logs.push(`✓ field ${key} exists`);
          } else {
            logs.push(`POST ${createURL}`);
            const createRes = await fetch(createURL, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                key,
                name,
                entity_type: entityType,
                field_type: 'text',
                order: 1,
                default_value: JSON.stringify(''),
              }),
            });
            if (createRes.ok) {
              logs.push(`✓ field ${key} created`);
            } else {
              const body = await createRes.text();
              logs.push(`⚠ could not create field ${key}: ${body}`);
            }
          }
        } catch (e) {
          logs.push(`⚠ custom fields check failed: ${e.message}`);
        }
      }

      await ensureField('spool', 'card_uids', 'Card UIDs');
      await ensureField('filament', 'variant', 'Variant');

      return { logs, error: null };
    } catch (e) {
      let msg = e.name === 'AbortError' ? 'Connection timed out' : e.message;
      if (e.name === 'TypeError' && msg.toLowerCase().includes('fetch')) {
        msg = 'Network error — is the URL correct? Spoolman must use HTTPS and have CORS enabled (set SPOOLMAN_CORS_ORIGIN=* in its environment variables).';
      }
      logs.push(`✗ ${msg}`);
      return { logs, error: msg };
    }
  }
}

// ─── Constants ───────────────────────────────────────────────────────────────

const MATERIAL_DENSITY = {
  PLA: 1.24, PETG: 1.27, ABS: 1.04, ASA: 1.07,
  TPU: 1.21, NYLON: 1.12, PA: 1.12, PC: 1.19,
  PVA: 1.19, HIPS: 1.04, PP: 0.9,
};

const MATERIAL_TEMPS = {
  PLA:   { nozzle: 220, bed: 60 },
  PETG:  { nozzle: 240, bed: 80 },
  ABS:   { nozzle: 250, bed: 100 },
  ASA:   { nozzle: 255, bed: 100 },
  TPU:   { nozzle: 230, bed: 50 },
  NYLON: { nozzle: 260, bed: 90 },
  PA:    { nozzle: 260, bed: 90 },
  PC:    { nozzle: 270, bed: 110 },
};

const WEIGHT_PRESETS = [250, 500, 750, 1000, 1500, 2000];

const NAME_STYLES = {
  brandAndSubtype:           (b, mat, sub, col) => [b, sub ?? mat],
  brandMaterialSubtype:      (b, mat, sub, col) => [b, mat, sub],
  materialAndSubtype:        (b, mat, sub, col) => [mat, sub],
  subtypeOnly:               (b, mat, sub, col) => [sub],
  brandColorSubtype:         (b, mat, sub, col) => [b, col, sub ?? mat],
  brandMaterialColorSubtype: (b, mat, sub, col) => [b, mat, col, sub],
  colorMaterialSubtype:      (b, mat, sub, col) => [col, mat, sub],
  colorOnly:                 (b, mat, sub, col) => [col],
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

function normalizeURL(url) {
  let s = url.trim();
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://' + s;
  if (!s.endsWith('/')) s += '/';
  return s;
}

function spoolDisplayName(spool) {
  const parts = [spool.filament?.vendor?.name, spool.filament?.name]
    .filter(Boolean);
  return parts.length ? parts.join(' – ') : 'Unnamed Spool';
}

function spoolTagUIDs(spool) {
  const raw = spool.extra?.card_uids;
  if (!raw) return [];
  let decoded = raw;
  try {
    decoded = JSON.parse(raw);
  } catch {}
  return decoded.split(',').map(s => s.trim()).filter(Boolean);
}

function colorName(hex) {
  if (!hex) return null;
  const h = hex.replace('#', '');
  if (h.length !== 6) return null;
  const rv = parseInt(h.slice(0, 2), 16);
  const gv = parseInt(h.slice(2, 4), 16);
  const bv = parseInt(h.slice(4, 6), 16);
  const r = rv / 255, g = gv / 255, b = bv / 255;
  const maxC = Math.max(r, g, b), minC = Math.min(r, g, b), delta = maxC - minC;
  const l = (maxC + minC) / 2;
  if (delta < 0.12) {
    if (l > 0.85) return 'White';
    if (l < 0.15) return 'Black';
    return 'Gray';
  }
  const s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC);
  if (s < 0.15) return l > 0.7 ? 'Silver' : 'Gray';
  let hue;
  if (maxC === r) { hue = ((g - b) / delta) % 6; if (hue < 0) hue += 6; }
  else if (maxC === g) { hue = (b - r) / delta + 2; }
  else { hue = (r - g) / delta + 4; }
  hue *= 60;
  if (hue >= 10 && hue < 40 && l < 0.45) return 'Brown';
  if (hue < 15) return 'Red';
  if (hue < 40) return 'Orange';
  if (hue < 65) return 'Yellow';
  if (hue < 165) return 'Green';
  if (hue < 195) return 'Cyan';
  if (hue < 255) return 'Blue';
  if (hue < 285) return 'Purple';
  if (hue < 325) return 'Magenta';
  if (hue < 345) return 'Pink';
  return 'Red';
}

function filamentName(meta, style) {
  const fn = NAME_STYLES[style] ?? NAME_STYLES.brandAndSubtype;
  const norm = v => (v && v.trim()) ? v.trim() : null;
  const parts = fn(norm(meta.brand), norm(meta.material), norm(meta.subtype), colorName(meta.colorHex))
    .filter(Boolean);
  const deduped = parts.filter((p, i) =>
    i === 0 || p.toLowerCase() !== parts[i - 1].toLowerCase());
  return deduped.length ? deduped.join(' ') : 'Custom Filament';
}

function parseOpenSpoolRecord(record) {
  try {
    if (record.recordType !== 'mime' || record.mediaType !== 'application/json') return null;
    const text = new TextDecoder().decode(record.data);
    const json = JSON.parse(text);
    if (json.protocol !== 'openspool') return null;
    return {
      format: 'openspool',
      version: json.version ?? '1.0',
      type: json.type ?? '',
      subtype: json.subtype ?? null,
      brand: json.brand ?? null,
      colorHex: json.color_hex ?? null,
      minTemp: json.min_temp ?? null,
      maxTemp: json.max_temp ?? null,
      bedMinTemp: json.bed_min_temp ?? null,
      bedMaxTemp: json.bed_max_temp ?? null,
      weight: json.weight ?? null,
      diameter: json.diameter ?? null,
      spoolId: json.spool_id ?? null,
    };
  } catch { return null; }
}

function tagPayloadFromNDEF(message) {
  for (const record of message.records) {
    const parsed = parseOpenSpoolRecord(record);
    if (parsed) return { kind: 'openspool', data: parsed };
  }
  const firstRecord = message.records[0];
  return {
    kind: 'raw',
    data: {
      mimeType: firstRecord?.mediaType ?? null,
      recordCount: message.records.length,
    },
  };
}

function tagFormatName(payload) {
  if (payload.kind === 'openspool') return `OpenSpool ${payload.data.version}`;
  return 'NDEF';
}

function tagFields(payload) {
  const fields = [];
  if (payload.kind === 'openspool') {
    const d = payload.data;
    if (d.type) fields.push({ label: 'Type', value: d.type.replace(/^./, c => c.toUpperCase()) });
    if (d.subtype) fields.push({ label: 'Material', value: d.subtype });
    if (d.brand) fields.push({ label: 'Brand', value: d.brand });
    if (d.colorHex) fields.push({ label: 'Color', value: `#${d.colorHex.toUpperCase()}`, colorHex: d.colorHex });
    if (d.minTemp != null && d.maxTemp != null) fields.push({ label: 'Nozzle', value: `${d.minTemp}–${d.maxTemp} °C` });
    if (d.bedMinTemp != null && d.bedMaxTemp != null) fields.push({ label: 'Bed', value: `${d.bedMinTemp}–${d.bedMaxTemp} °C` });
    if (d.weight != null) fields.push({ label: 'Weight', value: `${Math.round(d.weight)} g` });
    if (d.diameter != null) fields.push({ label: 'Diameter', value: `${d.diameter} mm` });
    if (d.spoolId != null) fields.push({ label: 'Spool ID', value: `#${d.spoolId}` });
  } else {
    const d = payload.data;
    if (d.mimeType) fields.push({ label: 'MIME Type', value: d.mimeType });
    if (d.recordCount > 0) fields.push({ label: 'Records', value: `${d.recordCount}` });
    if (d.payloadSize > 0) fields.push({ label: 'Payload', value: `${d.payloadSize} B` });
  }
  return fields;
}

function tagSpoolId(payload) {
  return payload.kind === 'openspool' ? payload.data.spoolId : null;
}

function tagDisplayTitle(payload) {
  if (payload.kind !== 'openspool') return 'Unknown Tag';
  const d = payload.data;
  const parts = [d.brand, d.subtype ?? d.type?.replace(/^./, c => c.toUpperCase())]
    .filter(Boolean);
  return parts.length ? parts.join(' ') : d.type?.replace(/^./, c => c.toUpperCase()) ?? 'Unknown';
}

function tagFilamentMeta(payload) {
  if (payload.kind !== 'openspool') return null;
  const d = payload.data;
  return {
    brand: d.brand,
    material: d.type ? d.type.toUpperCase() : null,
    subtype: d.subtype,
    colorHex: d.colorHex,
    diameter: d.diameter,
    weight: d.weight,
    nozzleTemp: d.maxTemp ? parseInt(d.maxTemp) : null,
    bedTemp: d.bedMaxTemp ? parseInt(d.bedMaxTemp) : null,
    spoolId: d.spoolId,
  };
}

function el(tag, attrs = {}, ...children) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'style') Object.assign(e.style, v);
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c == null) continue;
    e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

function colorSwatchEl(hex, size, radius) {
  const div = el('div', { class: 'color-swatch', style: { width: `${size}px`, height: `${size}px`, borderRadius: `${radius}px` } });
  if (hex) {
    div.style.background = `#${hex}`;
  } else {
    div.style.background = 'rgba(142,142,147,0.12)';
    div.innerHTML = `<svg width="${size * 0.4}" height="${size * 0.4}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/></svg>`;
  }
  return div;
}

function timeStr(date) {
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function dateTimeStr(date) {
  return date.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

// ─── Settings ────────────────────────────────────────────────────────────────

const Settings = {
  get baseURL() { return localStorage.getItem('spoolmanBaseURL') ?? 'http://spoolman.local:7912'; },
  set baseURL(v) { localStorage.setItem('spoolmanBaseURL', v); },
  get nameStyle() { return localStorage.getItem('filamentNameStyle') ?? 'brandAndSubtype'; },
  set nameStyle(v) { localStorage.setItem('filamentNameStyle', v); },
  get presets() {
    const defaults = { brands: [], materials: ['PLA','PETG','ABS','ASA','TPU','Nylon','PC','PA'], variants: ['Basic','Matte','Silk','Glossy','Carbon Fiber'], weights: ['250','500','1000','2000'] };
    try { return { ...defaults, ...(JSON.parse(localStorage.getItem('filamentPresets') ?? 'null') ?? {}) }; }
    catch { return defaults; }
  },
  set presets(v) { localStorage.setItem('filamentPresets', JSON.stringify(v)); },
};

// ─── App State ───────────────────────────────────────────────────────────────

const state = {
  spools: [],
  isFetchingSpools: false,
  hasMoreSpools: false,
  spoolsOffset: 0,
  spoolsPageSize: 20,
  isScanning: false,
  statusMessage: 'Ready to scan',
  scanHistory: [],
  lastResult: null,
  nfcSupported: 'NDEFReader' in window,
  activeTab: 'scan',
  sortBy: localStorage.getItem('spoolsSortBy') ?? 'dateAdded',
  sortAscending: localStorage.getItem('spoolsSortAscending') !== 'false',
  pendingAssignSpool: null,
};

const api = new SpoolmanAPI(Settings.baseURL);
api.ensureCardUidsFieldExists().catch(() => {});

// ─── NFC ─────────────────────────────────────────────────────────────────────

let nfcReader = null;
let nfcAbortController = null;

async function startNFC() {
  if (!state.nfcSupported) return;
  try {
    nfcAbortController = new AbortController();
    nfcReader = new NDEFReader();
    await nfcReader.scan({ signal: nfcAbortController.signal });
    nfcReader.addEventListener('reading', ({ message, serialNumber }) => {
      const uidHex = serialNumber.replace(/:/g, '').toUpperCase();
      const payload = tagPayloadFromNDEF(message);
      stopNFC();
      updateStatus('Tag detected');
      handleTagRead(payload, uidHex);
    });
    nfcReader.addEventListener('readingerror', () => {
      stopNFC();
      updateStatus('Error reading tag');
      setScanningUI(false);
    });
  } catch (e) {
    stopNFC();
    updateStatus(`NFC error: ${e.message}`);
    setScanningUI(false);
  }
}

function stopNFC() {
  if (nfcAbortController) { nfcAbortController.abort(); nfcAbortController = null; }
  nfcReader = null;
  state.isScanning = false;
}

// ─── Core Logic ──────────────────────────────────────────────────────────────

async function processTag(payload, uidHex) {
  const spoolId = tagSpoolId(payload);

  if (!spoolId) {
    let foundSpool = null;
    try { foundSpool = (await api.findSpoolsByCardUid(uidHex))[0] ?? null; } catch {}
    const result = {
      id: crypto.randomUUID(),
      timestamp: new Date(),
      spoolId: foundSpool?.id ?? null,
      spoolName: foundSpool ? spoolDisplayName(foundSpool) : tagDisplayTitle(payload),
      cardUid: uidHex,
      success: true,
      message: 'Tag read (no Spoolman link)',
      payload,
      spoolResponse: foundSpool,
    };
    updateStatus(`Tag read: ${tagDisplayTitle(payload)}`);
    addToHistory(result);
    renderScanResult(result);
    return;
  }

  updateStatus(`Fetching spool ${spoolId}…`);
  try {
    const spool = await api.getSpool(spoolId);
    const currentUIDs = spoolTagUIDs(spool);
    const updatedUIDs = currentUIDs.includes(uidHex) ? currentUIDs : [...currentUIDs, uidHex];

    updateStatus('Updating spool…');
    await api.updateSpoolCardUids(spoolId, updatedUIDs);

    updateStatus('Cleaning up other spools…');
    const matches = await api.findSpoolsByCardUid(uidHex);
    for (const other of matches) {
      if (other.id === spoolId) continue;
      const otherUIDs = spoolTagUIDs(other);
      const cleaned = otherUIDs.filter(uid => uid !== uidHex);
      if (cleaned.length !== otherUIDs.length) {
        await api.updateSpoolCardUids(other.id, cleaned);
        refreshSpoolInState(other.id);
      }
    }

    const updatedSpool = await refreshSpoolInState(spoolId) ?? spool;
    updateStatus(`Synced: ${spoolDisplayName(spool)}`);
    const result = {
      id: crypto.randomUUID(),
      timestamp: new Date(),
      spoolId,
      spoolName: spoolDisplayName(spool),
      cardUid: uidHex,
      success: true,
      message: 'Synced successfully',
      payload,
      spoolResponse: updatedSpool,
    };
    addToHistory(result);
    renderScanResult(result);

  } catch (e) {
    updateStatus(`Error: ${e.message}`);
    const result = {
      id: crypto.randomUUID(),
      timestamp: new Date(),
      spoolId,
      spoolName: tagDisplayTitle(payload),
      cardUid: uidHex,
      success: false,
      message: e.message,
      payload,
      spoolResponse: null,
    };
    addToHistory(result);
    renderScanResult(result);
  }
}

async function processAssignment(spool, uidHex, payload) {
  updateStatus(`Assigning tag to ${spoolDisplayName(spool)}…`);
  try {
    const currentUIDs = spoolTagUIDs(spool);
    const updatedUIDs = currentUIDs.includes(uidHex) ? currentUIDs : [...currentUIDs, uidHex];

    await api.updateSpoolCardUids(spool.id, updatedUIDs);

    const matches = await api.findSpoolsByCardUid(uidHex);
    for (const other of matches) {
      if (other.id === spool.id) continue;
      const otherUIDs = spoolTagUIDs(other);
      const cleaned = otherUIDs.filter(uid => uid !== uidHex);
      if (cleaned.length !== otherUIDs.length) {
        await api.updateSpoolCardUids(other.id, cleaned);
        refreshSpoolInState(other.id);
      }
    }

    const updatedSpool = await refreshSpoolInState(spool.id) ?? spool;
    updateStatus(`Tag assigned to ${spoolDisplayName(spool)}`);
    const result = {
      id: crypto.randomUUID(),
      timestamp: new Date(),
      spoolId: spool.id,
      spoolName: spoolDisplayName(spool),
      cardUid: uidHex,
      success: true,
      message: 'Tag assigned',
      payload,
      spoolResponse: updatedSpool,
    };
    addToHistory(result);
    renderScanResult(result);
  } catch (e) {
    updateStatus(`Error: ${e.message}`);
  }
}

async function createSpoolFromTag(uidHex, payload, meta) {
  const nameStyle = Settings.nameStyle;
  try {
    let vendorId = null;
    if (meta.brand) vendorId = await api.findOrCreateVendor(meta.brand);
    const name = meta.brand || meta.material ? filamentName(meta, nameStyle) : 'Custom Filament';
    const newSpool = await api.createSpoolFromInfo({
      filamentName: name,
      vendorId,
      material: meta.material || null,
      colorHex: meta.colorHex || null,
      diameter: parseFloat(meta.diameter) || 1.75,
      weight: meta.weight ? parseFloat(meta.weight) : null,
      nozzleTemp: meta.nozzleTemp ? parseInt(meta.nozzleTemp) : null,
      bedTemp: meta.bedTemp ? parseInt(meta.bedTemp) : null,
      cardUid: uidHex,
      subtype: meta.subtype || null,
    });
    updateStatus(`Spool created: ${spoolDisplayName(newSpool)}`);
    if (state.spools.length > 0) await refreshSpoolInState(newSpool.id);
    return newSpool;
  } catch (e) {
    updateStatus(`Error creating spool: ${e.message}`);
    return null;
  }
}

async function removeTag(spool, uidHex) {
  const updatedUIDs = spoolTagUIDs(spool).filter(u => u.toUpperCase() !== uidHex.toUpperCase());
  await api.updateSpoolCardUids(spool.id, updatedUIDs);
  await refreshSpoolInState(spool.id);
  if (state.lastResult?.spoolId === spool.id) {
    state.lastResult = { ...state.lastResult, spoolResponse: null, spoolId: null };
    renderScanResult(state.lastResult);
    updateStatus(`Tag unlinked from ${spoolDisplayName(spool)}`);
  }
}

async function removeAllTags(spool) {
  await api.updateSpoolCardUids(spool.id, []);
  await refreshSpoolInState(spool.id);
  if (state.lastResult?.spoolId === spool.id) {
    state.lastResult = { ...state.lastResult, spoolResponse: null, spoolId: null };
    renderScanResult(state.lastResult);
    updateStatus(`Tag unlinked from ${spoolDisplayName(spool)}`);
  }
}

async function refreshSpoolInState(id) {
  try {
    const updated = await api.getSpool(id);
    const idx = state.spools.findIndex(s => s.id === id);
    if (idx !== -1) state.spools[idx] = updated;
    for (let i = 0; i < state.scanHistory.length; i++) {
      if (state.scanHistory[i].spoolId === id) {
        state.scanHistory[i] = { ...state.scanHistory[i], spoolResponse: updated };
      }
    }
    if (state.lastResult?.spoolId === id) {
      state.lastResult = { ...state.lastResult, spoolResponse: updated };
    }
    return updated;
  } catch { return null; }
}

function addToHistory(result) {
  state.scanHistory.unshift(result);
  state.lastResult = result;
  updateHistoryBadge();
}

// ─── Spool list management ────────────────────────────────────────────────────

async function fetchSpools(reset = true) {
  if (state.isFetchingSpools) return;
  const offset = reset ? 0 : state.spoolsOffset;
  state.isFetchingSpools = true;
  if (reset) renderSpoolsLoading();
  try {
    const page = await api.fetchSpools(state.spoolsPageSize, offset);
    const active = page.filter(s => !s.archived);
    if (reset) { state.spools = active; state.spoolsOffset = 0; }
    else state.spools.push(...active);
    state.spoolsOffset = offset + page.length;
    state.hasMoreSpools = page.length === state.spoolsPageSize;
  } catch (e) {
    if (reset) state.spools = [];
  }
  state.isFetchingSpools = false;
  renderSpools();
}

function ensureSpoolsLoaded() {
  if (state.spools.length === 0 && !state.isFetchingSpools) fetchSpools();
}

// ─── Sorting ──────────────────────────────────────────────────────────────────

function sectionHeader(spool, sort) {
  const cal = (d, ref) => {
    const ms = ref - d;
    return Math.floor(ms / 86400000);
  };
  const now = Date.now();
  switch (sort) {
    case 'dateAdded': {
      if (!spool.registered) return 'Unknown';
      const d = cal(new Date(spool.registered).getTime(), now);
      if (d <= 0) return 'Today';
      if (d <= 3) return 'Last 3 Days';
      if (d <= 7) return 'This Week';
      if (d <= 30) return 'This Month';
      return 'Older';
    }
    case 'lastUsed': {
      if (!spool.last_used) return 'Never Used';
      const d = cal(new Date(spool.last_used).getTime(), now);
      if (d <= 0) return 'Today';
      if (d <= 3) return 'Last 3 Days';
      if (d <= 7) return 'This Week';
      if (d <= 30) return 'This Month';
      return 'Older';
    }
    case 'name': {
      const c = spoolDisplayName(spool)[0]?.toUpperCase() ?? '#';
      if (c >= 'A' && c <= 'E') return 'A – E';
      if (c >= 'F' && c <= 'J') return 'F – J';
      if (c >= 'K' && c <= 'O') return 'K – O';
      if (c >= 'P' && c <= 'T') return 'P – T';
      if (c >= 'U' && c <= 'Z') return 'U – Z';
      return '#';
    }
    case 'material': return spool.filament?.material ?? 'Unknown';
    case 'remaining': {
      const w = spool.remaining_weight;
      if (w == null) return 'Unknown';
      if (w === 0) return 'Empty';
      if (w < 100) return '< 100 g';
      if (w < 500) return '100 – 500 g';
      return '> 500 g';
    }
    case 'tags': {
      const n = spoolTagUIDs(spool).length;
      if (n === 0) return 'No Tags';
      if (n === 1) return '1 Tag';
      return 'Multiple Tags';
    }
  }
  return '';
}

function sortCompare(a, b, sort, asc) {
  const flip = v => asc ? v : -v;
  switch (sort) {
    case 'dateAdded': return flip(new Date(b.registered ?? 0) - new Date(a.registered ?? 0));
    case 'lastUsed':  return flip(new Date(b.last_used ?? 0) - new Date(a.last_used ?? 0));
    case 'name':      return flip(spoolDisplayName(a).localeCompare(spoolDisplayName(b)));
    case 'material':  return flip((a.filament?.material ?? '').localeCompare(b.filament?.material ?? ''));
    case 'remaining': return flip((b.remaining_weight ?? 0) - (a.remaining_weight ?? 0));
    case 'tags':      return flip(spoolTagUIDs(b).length - spoolTagUIDs(a).length);
  }
  return 0;
}

function computeDuplicateTagUIDs(spools) {
  const counts = {};
  for (const s of spools) {
    for (const uid of spoolTagUIDs(s)) counts[uid] = (counts[uid] ?? 0) + 1;
  }
  return new Set(Object.entries(counts).filter(([, v]) => v > 1).map(([k]) => k));
}

function groupSpools(spools, sort, asc) {
  const sorted = [...spools].sort((a, b) => sortCompare(a, b, sort, asc));
  const groups = [];
  for (const spool of sorted) {
    const h = sectionHeader(spool, sort);
    if (groups.length && groups[groups.length - 1].header === h) {
      groups[groups.length - 1].items.push(spool);
    } else {
      groups.push({ header: h, items: [spool] });
    }
  }
  return groups;
}

// ─── UI state helpers ─────────────────────────────────────────────────────────

function updateStatus(msg) {
  state.statusMessage = msg;
  const el = document.getElementById('scan-status');
  if (el) el.textContent = msg;
}

function setScanningUI(scanning) {
  state.isScanning = scanning;
  const circle = document.getElementById('scan-circle');
  const icon = document.getElementById('scan-icon');
  const spinner = document.getElementById('scan-spinner');
  const btn = document.getElementById('btn-scan');
  if (!circle) return;
  if (scanning) {
    circle.className = 'scan-circle scanning';
    icon.classList.add('hidden');
    spinner.classList.remove('hidden');
    btn.className = 'btn btn-stop btn-full';
    btn.innerHTML = `<svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M6 6h12v12H6z"/></svg> Stop Scanning`;
  } else {
    circle.className = 'scan-circle idle';
    icon.classList.remove('hidden');
    spinner.classList.add('hidden');
    btn.className = 'btn btn-primary btn-full';
    btn.innerHTML = `<svg class="btn-icon" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/></svg> Start Scanning`;
  }
}

function updateHistoryBadge() {
  const badge = document.getElementById('history-badge');
  const n = state.scanHistory.length;
  if (n > 0) {
    badge.textContent = n > 99 ? '99+' : n;
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}

function showToast(msg, iconHtml = '') {
  const toast = document.getElementById('toast');
  toast.innerHTML = iconHtml ? `${iconHtml}<span>${msg}</span>` : msg;
  toast.classList.remove('hidden');
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => toast.classList.add('hidden'), 2000);
}

function showModal(id) {
  document.getElementById('modal-overlay').classList.remove('hidden');
  document.getElementById(id).classList.remove('hidden');
}

function hideModal(id) {
  document.getElementById(id).classList.add('hidden');
  const remaining = ['modal-spool', 'modal-assign', 'modal-create', 'modal-preset', 'modal-preset-editor', 'modal-history']
    .some(m => m !== id && !document.getElementById(m).classList.contains('hidden'));
  if (!remaining) document.getElementById('modal-overlay').classList.add('hidden');
}

function showConfirm(title, desc, destructiveLabel, onConfirm) {
  const overlay = el('div', { class: 'confirm-overlay', onclick: e => { if (e.target === overlay) overlay.remove(); } },
    el('div', { class: 'confirm-card' },
      el('div', { class: 'confirm-body' },
        el('div', { class: 'confirm-title' }, title),
        desc ? el('div', { class: 'confirm-desc' }, desc) : null,
      ),
      el('div', { class: 'confirm-actions' },
        el('button', { class: 'confirm-btn', onclick: () => overlay.remove() }, 'Cancel'),
        el('button', { class: 'confirm-btn destructive', onclick: () => { overlay.remove(); onConfirm(); } }, destructiveLabel),
      ),
    ),
  );
  document.body.appendChild(overlay);
}

// ─── Scan tab rendering ───────────────────────────────────────────────────────

function handleTagRead(payload, uidHex) {
  setScanningUI(false);
  updateStatus('Processing…');
  if (state.pendingAssignSpool) {
    const spool = state.pendingAssignSpool;
    state.pendingAssignSpool = null;
    processAssignment(spool, uidHex, payload).then(() => {
      const updated = state.spools.find(s => s.id === spool.id) ?? spool;
      showSpoolDetail(updated);
    });
  } else {
    processTag(payload, uidHex);
  }
}

function renderScanResult(result) {
  const container = document.getElementById('scan-result');
  container.innerHTML = '';
  container.classList.remove('hidden');

  const iconSvg = result.success
    ? `<svg class="result-icon success" viewBox="0 0 24 24" fill="currentColor"><path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`
    : `<svg class="result-icon failure" viewBox="0 0 24 24" fill="currentColor"><path d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`;

  container.appendChild(
    el('div', { class: 'result-header' },
      el('span', {}, ...parseHTML(iconSvg)),
      el('span', { class: `result-label ${result.success ? 'success' : 'failure'}` }, result.success ? 'Tag read' : 'Error'),
      el('span', { class: 'result-time' }, timeStr(result.timestamp)),
    )
  );

  container.appendChild(renderTagDetailTable(result.payload, result.cardUid));

  if (result.spoolResponse) {
    const wrap = el('div', {});
    wrap.appendChild(renderSpoolmanSection(() => renderSpoolInfoRow(result.spoolResponse, wrap)));
    container.appendChild(wrap);
  } else if (result.success) {
    const wrap = el('div', {});
    const assignBtn = el('button', { class: 'btn btn-secondary btn-full', onclick: () => showAssignModal(result.payload, result.cardUid) },
      ...parseHTML(`<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" stroke-linecap="round" stroke-linejoin="round"/></svg>`),
      document.createTextNode('Assign to Existing Spool'),
    );
    const createBtn = el('button', { class: 'btn btn-primary btn-full', onclick: () => showCreateModal(result.payload, result.cardUid) },
      ...parseHTML(`<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 8v8m-4-4h8" stroke-linecap="round"/></svg>`),
      document.createTextNode('Create New Spool'),
    );
    const actions = el('div', { class: 'spool-actions' }, assignBtn, createBtn);
    wrap.appendChild(renderSpoolmanSection(() => actions));
    container.appendChild(wrap);
  }
}

function parseHTML(html) {
  const t = document.createElement('template');
  t.innerHTML = html;
  return Array.from(t.content.childNodes);
}

function renderTagDetailTable(payload, uidHex) {
  const table = el('div', { class: 'tag-table' });

  const rows = [
    ['Format', el('span', { class: 'tag-row-value' }, tagFormatName(payload))],
    ...tagFields(payload).map(field => {
      if (field.colorHex) {
        const s = el('span', { class: 'tag-row-value' });
        s.appendChild(el('span', { class: 'color-swatch-row' },
          el('span', { class: 'color-dot', style: { background: `#${field.colorHex}` } }),
          el('span', { class: 'mono' }, field.value),
        ));
        return [field.label, s];
      }
      return [field.label, el('span', { class: 'tag-row-value' }, field.value)];
    }),
    ['Card UID', el('span', { class: 'tag-row-value mono' }, uidHex)],
  ];

  for (let i = 0; i < rows.length; i++) {
    if (i > 0) {
      table.appendChild(el('div', { style: { height: '1px', background: 'var(--separator)', marginLeft: '16px' } }));
    }
    const row = el('div', { class: 'tag-row' },
      el('span', { class: 'tag-row-label' }, rows[i][0]),
      rows[i][1],
    );
    table.appendChild(row);
  }

  return table;
}

function renderSpoolmanSection(contentFn) {
  const wrap = el('div', { style: { marginTop: '12px' } });
  wrap.appendChild(el('div', { class: 'section-label' },
    ...parseHTML(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 21h8m-4-4v4" stroke-linecap="round"/></svg>`),
    document.createTextNode('Spoolman'),
  ));
  wrap.appendChild(contentFn());
  return wrap;
}

function renderSpoolInfoRow(spool, scanResultContainer) {
  const row = el('div', { class: 'spool-info-row', onclick: () => showSpoolDetail(spool) });
  row.appendChild(colorSwatchEl(spool.filament?.color_hex, 36, 8));
  const info = el('div', { style: { flex: '1', minWidth: '0' } });
  info.appendChild(el('div', { class: 'spool-info-name' }, spoolDisplayName(spool)));
  const meta = el('div', { class: 'spool-info-meta' });
  if (spool.filament?.material) meta.appendChild(el('span', { class: 'chip' }, spool.filament.material));
  if (spool.remaining_weight != null) meta.appendChild(el('span', { style: { fontSize: '12px', color: 'var(--label-secondary)' } }, `${Math.round(spool.remaining_weight)} g left`));
  const tagCount = spoolTagUIDs(spool).length;
  meta.appendChild(el('span', { class: 'chip blue' }, `Tags ${tagCount}`));
  info.appendChild(meta);
  row.appendChild(info);

  const wrap = el('div', { style: { marginBottom: '8px' } });
  wrap.appendChild(row);
  if (state.spools.length > 0) {
    const changeBtn = el('button', { class: 'btn btn-secondary btn-full', style: { marginTop: '8px' },
      onclick: () => showAssignModal(state.lastResult?.payload ?? { kind: 'raw', data: {} }, spool.id ? state.lastResult?.cardUid ?? '' : '') },
      `Change Spool`,
    );
    wrap.appendChild(changeBtn);
  }
  const cardUid = state.lastResult?.cardUid ?? '';
  const unlinkBtn = el('button', { class: 'btn btn-danger btn-full', style: { marginTop: '8px' },
    onclick: () => {
      if (confirm(`Unlink ${cardUid} from ${spoolDisplayName(spool)}?`)) {
        removeTag(spool, cardUid);
      }
    }},
    `Unlink from Spool`,
  );
  wrap.appendChild(unlinkBtn);
  return wrap;
}

// ─── Spools tab rendering ─────────────────────────────────────────────────────

function renderSpools() {
  const list = document.getElementById('spools-list');
  list.innerHTML = '';

  if (state.isFetchingSpools && state.spools.length === 0) {
    list.appendChild(el('div', { class: 'loading-row' }, el('div', { class: 'spinner' })));
    return;
  }

  if (state.spools.length === 0) {
    list.appendChild(el('div', { class: 'empty-state' },
      ...parseHTML(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"/></svg>`),
      el('div', { class: 'empty-state-title' }, 'No Spools'),
      el('div', { class: 'empty-state-desc' }, 'No spools found in Spoolman'),
    ));
    return;
  }

  const groups = groupSpools(state.spools, state.sortBy, state.sortAscending);
  renderSpoolCards(list, groups);
}

function renderSpoolCards(list, groups) {
  list.innerHTML = '';
  const duplicateUIDs = computeDuplicateTagUIDs(state.spools);
  for (const group of groups) {
    list.appendChild(el('div', { class: 'spool-section-header' }, group.header));
    const section = el('div', { style: { margin: '0 16px 4px', background: 'var(--bg-card-solid)', borderRadius: '12px', border: '1px solid var(--separator)', overflow: 'hidden' } });
    for (let i = 0; i < group.items.length; i++) {
      const spool = group.items[i];
      if (i > 0) section.appendChild(el('div', { class: 'spool-row-divider' }));
      const row = el('div', { class: 'spool-row', onclick: () => showSpoolDetail(spool) });
      row.appendChild(colorSwatchEl(spool.filament?.color_hex, 44, 10));
      const info = el('div', { class: 'spool-row-info' });
      info.appendChild(el('div', { class: 'spool-row-name' }, spoolDisplayName(spool)));
      const meta = el('div', { class: 'spool-row-meta' });
      if (spool.filament?.material) meta.appendChild(el('span', { class: 'chip' }, spool.filament.material));
      meta.appendChild(el('span', { class: 'spool-id' }, `#${spool.id}`));
      if (spool.remaining_weight != null) {
        meta.appendChild(el('span', {}, '·'));
        meta.appendChild(el('span', {}, `${Math.round(spool.remaining_weight)} g`));
      }
      meta.appendChild(el('span', {}, '·'));
      const tagCount = spoolTagUIDs(spool).length;
      meta.appendChild(el('span', { class: 'chip blue' }, `Tags ${tagCount}`));
      info.appendChild(meta);
      row.appendChild(info);
      const hasConflict = spoolTagUIDs(spool).some(uid => duplicateUIDs.has(uid));
      if (hasConflict) {
        const warn = document.createElement('div');
        warn.innerHTML = `<svg style="width:14px;height:14px;color:var(--orange);flex-shrink:0" viewBox="0 0 24 24" fill="currentColor"><path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>`;
        row.appendChild(warn.firstChild);
      }
      const chevron = document.createElement('div');
      chevron.innerHTML = `<svg style="width:14px;height:14px;color:var(--label-tertiary);flex-shrink:0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 5l7 7-7 7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
      row.appendChild(chevron.firstChild);
      section.appendChild(row);
    }
    list.appendChild(section);
  }

  if (state.hasMoreSpools) {
    const loadRow = el('div', { class: 'load-more-row' });
    if (state.isFetchingSpools) {
      loadRow.appendChild(el('div', { class: 'spinner' }));
    } else {
      const btn = el('button', { class: 'btn btn-secondary', onclick: () => fetchSpools(false) }, 'Load More');
      loadRow.appendChild(btn);
    }
    list.appendChild(loadRow);
  }
}

// ─── Spool detail modal ───────────────────────────────────────────────────────

function showSpoolDetail(spool) {
  const body = document.getElementById('modal-spool-body');
  body.innerHTML = '';

  const header = el('div', { class: 'spool-detail-header' });
  header.appendChild(colorSwatchEl(spool.filament?.color_hex, 64, 14));
  const headerInfo = el('div', {});
  headerInfo.appendChild(el('div', { class: 'spool-detail-name' }, spoolDisplayName(spool)));
  const chips = el('div', { class: 'spool-info-meta' });
  if (spool.filament?.material) chips.appendChild(el('span', { class: 'chip' }, spool.filament.material));
  const tagCount = spoolTagUIDs(spool).length;
  chips.appendChild(el('span', { class: 'chip blue' }, `Tags ${tagCount}`));
  headerInfo.appendChild(chips);
  header.appendChild(headerInfo);
  body.appendChild(header);

  const statsSection = el('div', { style: { margin: '0 16px 12px', background: 'var(--bg-card-solid)', borderRadius: '12px', border: '1px solid var(--separator)', overflow: 'hidden' } });
  const addStat = (label, value, mono = false) => {
    if (statsSection.children.length) statsSection.appendChild(el('div', { style: { height: '1px', background: 'var(--separator)', marginLeft: '16px' } }));
    statsSection.appendChild(el('div', { class: 'form-row form-row-kv' },
      el('span', { class: 'form-label', style: { color: 'var(--label-secondary)' } }, label),
      el('span', { class: `form-value-secondary${mono ? ' mono' : ''}` }, value),
    ));
  };
  const addStatEl = (label, node) => {
    if (statsSection.children.length) statsSection.appendChild(el('div', { style: { height: '1px', background: 'var(--separator)', marginLeft: '16px' } }));
    statsSection.appendChild(el('div', { class: 'form-row form-row-kv' },
      el('span', { class: 'form-label', style: { color: 'var(--label-secondary)' } }, label),
      node,
    ));
  };
  addStat('Spool ID', `#${spool.id}`);
  if (spool.remaining_weight != null) addStat('Remaining', `${Math.round(spool.remaining_weight)} g`);
  if (spool.filament?.color_hex) {
    const colorEl = el('div', { class: 'color-swatch-row' },
      el('div', { class: 'color-dot', style: { background: `#${spool.filament.color_hex}`, width: '18px', height: '18px', borderRadius: '4px' } }),
      el('span', { class: 'mono', style: { fontSize: '14px' } }, `#${spool.filament.color_hex.toUpperCase()}`),
    );
    addStatEl('Color', colorEl);
  }
  if (spool.filament?.diameter != null) addStat('Diameter', `${spool.filament.diameter.toFixed(2)} mm`);
  if (spool.filament?.weight != null) addStat('Filament', `${Math.round(spool.filament.weight)} g`);
  if (spool.filament?.settings_extruder_temp != null) addStat('Nozzle', `${spool.filament.settings_extruder_temp} °C`);
  if (spool.filament?.settings_bed_temp != null) addStat('Bed', `${spool.filament.settings_bed_temp} °C`);
  if (spool.registered) addStat('Added', new Date(spool.registered).toLocaleDateString());
  if (spool.last_used) addStat('Last Used', new Date(spool.last_used).toLocaleDateString());
  body.appendChild(statsSection);

  const duplicateUIDs = computeDuplicateTagUIDs(state.spools);
  const tagsWrap = el('div', { class: 'tags-section', style: { margin: '0 16px 12px', background: 'var(--bg-card-solid)', borderRadius: '12px', border: '1px solid var(--separator)', overflow: 'hidden' } });
  const tagsHeader = el('div', { class: 'tags-section-header' });
  tagsHeader.appendChild(el('span', { class: 'tags-section-title' }, 'Assigned Tags'));
  const tagUIDs = spoolTagUIDs(spool);
  if (tagUIDs.length > 0) {
    const removeBtn = el('button', { class: 'tags-remove-btn', onclick: () => {
      showConfirm(
        `Remove all ${tagCount} tag${tagCount === 1 ? '' : 's'}?`,
        `Remove all tags from ${spoolDisplayName(spool)}?`,
        'Remove All Tags',
        async () => {
          await removeAllTags(spool);
          const updated = state.spools.find(s => s.id === spool.id) ?? spool;
          showSpoolDetail(updated);
          renderSpools();
        }
      );
    } }, 'Remove All');
    tagsHeader.appendChild(removeBtn);
  }
  tagsWrap.appendChild(tagsHeader);
  if (tagUIDs.length === 0) {
    tagsWrap.appendChild(el('div', { style: { padding: '0 16px 12px', fontSize: '15px', color: 'var(--label-secondary)' } }, 'No tags assigned'));
  } else {
    for (const uid of tagUIDs) {
      const warnHtml = duplicateUIDs.has(uid)
        ? `<svg style="width:12px;height:12px;color:var(--orange);flex-shrink:0;margin-left:6px" viewBox="0 0 24 24" fill="currentColor"><path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>`
        : '';
      tagsWrap.appendChild(el('div', { class: 'tag-uid-row' },
        ...parseHTML(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 8l1.5 8.5M8 5.5L17.5 15M5 8C3.343 8 2 6.657 2 5s1.343-3 3-3 3 1.343 3 3S6.657 8 5 8zm12.5 7C15.843 15 14.5 16.343 14.5 18s1.343 3 3 3 3-1.343 3-3-1.343-3-3-3z" stroke-linecap="round"/></svg>`),
        el('span', {}, uid),
        ...parseHTML(warnHtml),
      ));
    }
    if (tagUIDs.some(uid => duplicateUIDs.has(uid))) {
      tagsWrap.appendChild(el('div', { style: { height: '1px', background: 'var(--separator)', marginLeft: '16px' } }));
      tagsWrap.appendChild(el('div', { style: { display: 'flex', alignItems: 'center', gap: '6px', padding: '10px 16px', fontSize: '12px', color: 'var(--label-secondary)' } },
        ...parseHTML(`<svg style="width:12px;height:12px;color:var(--orange);flex-shrink:0" viewBox="0 0 24 24" fill="currentColor"><path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>`),
        document.createTextNode('One or more tags are assigned to multiple spools. Scan the tag to fix.'),
      ));
    }
  }
  body.appendChild(tagsWrap);
  body.appendChild(el('div', { style: { padding: '2px 16px 8px', fontSize: '12px', color: 'var(--label-secondary)' } },
    'Tip: assign a tag from each side of the spool.'));

  const actionsWrap = el('div', { style: { padding: '0 16px 8px', display: 'flex', flexDirection: 'column', gap: '10px' } });
  const isAssigning = state.pendingAssignSpool?.id === spool.id;
  const assignBtn = el('button', {
    class: `btn btn-full${isAssigning ? ' btn-secondary' : ' btn-primary'}`,
    disabled: !state.nfcSupported || undefined,
    onclick: () => {
      if (isAssigning) {
        state.pendingAssignSpool = null;
        stopNFC();
        updateStatus('Ready to scan');
        showSpoolDetail(spool);
      } else {
        state.pendingAssignSpool = spool;
        showSpoolDetail(spool);
        startNFC();
      }
    },
  },
    ...parseHTML(isAssigning
      ? `<div class="spinner" style="width:16px;height:16px;border-width:2px;flex-shrink:0"></div>`
      : `<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M7 7H4a2 2 0 00-2 2v9a2 2 0 002 2h16a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1-4l-3 3m0 0l-3-3m3 3V1" stroke-linecap="round" stroke-linejoin="round"/></svg>`),
    document.createTextNode(isAssigning ? 'Scanning for tag… (tap to cancel)' : 'Assign NFC Tag'),
  );
  actionsWrap.appendChild(assignBtn);

  const base = Settings.baseURL.replace(/\/$/, '');
  const openLink = el('a', { href: `${base}/spool/show/${spool.id}`, target: '_blank', class: 'btn btn-secondary btn-full', style: { textDecoration: 'none' } },
    ...parseHTML(`<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" stroke-linecap="round" stroke-linejoin="round"/></svg>`),
    document.createTextNode('Open in Spoolman'),
  );
  actionsWrap.appendChild(openLink);
  body.appendChild(actionsWrap);

  showModal('modal-spool');
}

// ─── Assign modal ─────────────────────────────────────────────────────────────

function showAssignModal(payload, uidHex) {
  const searchInput = document.getElementById('assign-search');
  searchInput.value = '';
  renderAssignList(payload, uidHex, '');
  searchInput.oninput = () => renderAssignList(payload, uidHex, searchInput.value);
  showModal('modal-assign');
  ensureSpoolsLoaded();
}

function renderAssignList(payload, uidHex, query) {
  const body = document.getElementById('modal-assign-body');
  body.innerHTML = '';

  if (state.isFetchingSpools && state.spools.length === 0) {
    body.appendChild(el('div', { class: 'loading-row' }, el('div', { class: 'spinner' })));
    return;
  }

  let spools = state.spools;
  if (query) {
    const q = query.toLowerCase();
    spools = spools.filter(s =>
      spoolDisplayName(s).toLowerCase().includes(q) ||
      s.filament?.material?.toLowerCase().includes(q) ||
      s.filament?.vendor?.name?.toLowerCase().includes(q)
    );
  }

  if (spools.length === 0) {
    body.appendChild(el('div', { class: 'empty-state' },
      el('div', { class: 'empty-state-title' }, 'No Results'),
      el('div', { class: 'empty-state-desc' }, query ? `No spools matching "${query}"` : 'No spools available'),
    ));
    return;
  }

  const wrap = el('div', { class: 'assign-list-wrap' });
  for (const spool of spools) {
    const row = el('div', { class: 'assign-row', onclick: async () => {
      document.getElementById('modal-assign-overlay').classList.remove('hidden');
      await processAssignment(spool, uidHex, payload);
      document.getElementById('modal-assign-overlay').classList.add('hidden');
      hideModal('modal-assign');
    } });
    row.appendChild(colorSwatchEl(spool.filament?.color_hex, 40, 8));
    const info = el('div', { style: { flex: '1', minWidth: '0' } });
    info.appendChild(el('div', { style: { fontSize: '15px', fontWeight: '600', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' } }, spoolDisplayName(spool)));
    const meta = el('div', { class: 'spool-row-meta', style: { marginTop: '3px' } });
    meta.appendChild(el('span', { class: 'spool-id' }, `#${spool.id}`));
    if (spool.filament?.material) { meta.appendChild(el('span', {}, '·')); meta.appendChild(el('span', {}, spool.filament.material)); }
    if (spool.remaining_weight != null) { meta.appendChild(el('span', {}, '·')); meta.appendChild(el('span', {}, `${Math.round(spool.remaining_weight)} g`)); }
    meta.appendChild(el('span', {}, '·'));
    meta.appendChild(el('span', { class: 'chip blue' }, `Tags ${spoolTagUIDs(spool).length}`));
    info.appendChild(meta);
    row.appendChild(info);
    const chevron = document.createElement('div');
    chevron.innerHTML = `<svg style="width:14px;height:14px;color:var(--label-tertiary)" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 5l7 7-7 7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
    row.appendChild(chevron.firstChild);
    wrap.appendChild(row);
  }
  body.appendChild(wrap);
}

// ─── Create spool modal ───────────────────────────────────────────────────────

function showCreateModal(payload, uidHex) {
  const meta = tagFilamentMeta(payload) ?? {};
  document.getElementById('create-brand').value = meta.brand ?? '';
  document.getElementById('create-material').value = meta.material ?? '';
  document.getElementById('create-subtype').value = meta.subtype ?? '';
  const initialHex = (meta.colorHex ?? 'FFFFFF').replace('#', '').toUpperCase();
  document.getElementById('create-color-hex').value = initialHex;
  document.getElementById('create-color-picker').value = `#${initialHex}`;
  document.getElementById('create-diameter').value = meta.diameter ?? '1.75';
  document.getElementById('create-weight').value = meta.weight ?? '1000';
  document.getElementById('create-nozzle').value = meta.nozzleTemp ?? '';
  document.getElementById('create-bed').value = meta.bedTemp ?? '';
  document.getElementById('create-uid').textContent = uidHex;

  renderCreatePresetBtns();

  document.getElementById('modal-create-submit').onclick = async () => {
    const submitBtn = document.getElementById('modal-create-submit');
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<div class="spinner" style="width:16px;height:16px;border-width:2px"></div>';
    const overrideMeta = {
      brand: document.getElementById('create-brand').value.trim() || null,
      material: document.getElementById('create-material').value.trim() || null,
      subtype: document.getElementById('create-subtype').value.trim() || null,
      colorHex: document.getElementById('create-color-hex').value.trim() || null,
      diameter: document.getElementById('create-diameter').value || '1.75',
      weight: document.getElementById('create-weight').value || null,
      nozzleTemp: document.getElementById('create-nozzle').value || null,
      bedTemp: document.getElementById('create-bed').value || null,
    };
    const newSpool = await createSpoolFromTag(uidHex, payload, overrideMeta);
    submitBtn.disabled = false;
    submitBtn.textContent = 'Create';
    hideModal('modal-create');
    if (newSpool) {
      const result = {
        id: crypto.randomUUID(),
        timestamp: new Date(),
        spoolId: newSpool.id,
        spoolName: spoolDisplayName(newSpool),
        cardUid: uidHex,
        success: true,
        message: 'Spool created',
        payload,
        spoolResponse: newSpool,
      };
      state.scanHistory[0] = result;
      state.lastResult = result;
      renderScanResult(result);
      renderSpools();
      showToast(`Spool created: ${spoolDisplayName(newSpool)}`);
    }
  };

  showModal('modal-create');
  ensureSpoolsLoaded();
}

function renderWeightChips(currentVal) {
  const row = document.getElementById('weight-chips');
  row.innerHTML = '';
  for (const w of WEIGHT_PRESETS) {
    const chip = el('div', { class: `weight-chip${String(w) === String(currentVal) ? ' active' : ''}`, onclick: () => {
      document.getElementById('create-weight').value = w;
      renderWeightChips(w);
    } }, `${w} g`);
    row.appendChild(chip);
  }
}

function renderCreatePresetBtns() {
  const presets = Settings.presets;
  const spoolsBrands = [...new Set(state.spools.map(s => s.filament?.vendor?.name).filter(Boolean))].sort();
  const spoolsMaterials = [...new Set(state.spools.map(s => s.filament?.material).filter(Boolean))].sort();
  const brandSuggestions = [...presets.brands, ...spoolsBrands.filter(b => !presets.brands.includes(b))];
  const materialSuggestions = [...presets.materials, ...spoolsMaterials.filter(m => !presets.materials.includes(m))];
  const variantSuggestions = ['', ...presets.variants];

  const weightSuggestions = Settings.presets.weights ?? WEIGHT_PRESETS.map(String);
  const fieldMap = { brand: brandSuggestions, material: materialSuggestions, subtype: variantSuggestions, weight: weightSuggestions };

  document.querySelectorAll('.preset-btn').forEach(btn => {
    const field = btn.dataset.field;
    const inputId = `create-${field}`;
    btn.onclick = () => showPresetPicker(field.charAt(0).toUpperCase() + field.slice(1), fieldMap[field], val => {
      document.getElementById(inputId).value = val;
      if (field === 'material') applyMaterialTemps(val);
    });
  });
}

function applyMaterialTemps(material) {
  const key = material.trim().toUpperCase();
  const defaults = MATERIAL_TEMPS[key];
  if (!defaults) return;
  const nozzle = document.getElementById('create-nozzle');
  const bed = document.getElementById('create-bed');
  if (!nozzle.value) nozzle.value = defaults.nozzle;
  if (!bed.value) bed.value = defaults.bed;
}

// ─── Preset picker modal ──────────────────────────────────────────────────────

function showPresetPicker(title, items, onSelect) {
  document.getElementById('modal-preset-title').textContent = title;
  const searchInput = document.getElementById('preset-search');
  searchInput.value = '';
  renderPresetList(items, onSelect, '');
  searchInput.oninput = () => renderPresetList(items, onSelect, searchInput.value);
  document.getElementById('modal-preset-done').onclick = () => hideModal('modal-preset');
  document.getElementById('modal-preset-cancel').onclick = () => hideModal('modal-preset');
  showModal('modal-preset');
}

function renderPresetList(items, onSelect, query) {
  const body = document.getElementById('modal-preset-body');
  body.innerHTML = '';
  const filtered = query ? items.filter(i => i.toLowerCase().includes(query.toLowerCase())) : items;
  if (filtered.length === 0) {
    body.appendChild(el('div', { class: 'empty-state' }, el('div', { class: 'empty-state-desc' }, 'No results')));
    return;
  }
  const wrap = el('div', { class: 'preset-list-wrap' });
  for (const item of filtered) {
    const label = item === '' ? 'None' : item;
    const span = el('span', item === '' ? { style: 'color: var(--text-secondary)' } : {}, label);
    const row = el('div', { class: 'preset-item', onclick: () => {
      onSelect(item);
      hideModal('modal-preset');
    } }, span);
    wrap.appendChild(row);
  }
  body.appendChild(wrap);
}

// ─── History tab rendering ─────────────────────────────────────────────────────

function renderHistory() {
  const list = document.getElementById('history-list');
  const clearBtn = document.getElementById('btn-clear-history');
  list.innerHTML = '';

  if (state.scanHistory.length === 0) {
    clearBtn.classList.add('hidden');
    list.appendChild(el('div', { class: 'empty-state' },
      ...parseHTML(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/></svg>`),
      el('div', { class: 'empty-state-title' }, 'No Scan History'),
      el('div', { class: 'empty-state-desc' }, 'Scanned NFC tags will appear here'),
    ));
    return;
  }

  clearBtn.classList.remove('hidden');
  const card = el('div', { class: 'history-card' });
  for (const result of state.scanHistory) {
    const row = el('div', { class: 'history-row', onclick: () => showHistoryDetail(result) });
    const iconEl = el('div', { class: `history-icon ${result.success ? 'success' : 'failure'}` });
    iconEl.innerHTML = result.success
      ? `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`
      : `<svg viewBox="0 0 24 24" fill="currentColor"><path d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`;
    row.appendChild(iconEl);

    const info = el('div', { style: { flex: '1', minWidth: '0' } });
    const nameRow = el('div', { style: { display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '4px' } });
    nameRow.appendChild(el('span', { class: 'history-name' }, result.spoolName));
    const fmt = el('span', { class: 'format-badge' }, tagFormatName(result.payload));
    nameRow.appendChild(fmt);
    info.appendChild(nameRow);
    const metaRow = el('div', { class: 'history-meta' });
    if (result.spoolId) metaRow.appendChild(el('span', {}, `#${result.spoolId} `));
    metaRow.appendChild(el('span', {}, result.cardUid));
    info.appendChild(metaRow);
    info.appendChild(el('div', { class: 'history-time' }, dateTimeStr(result.timestamp)));
    row.appendChild(info);
    const chevron = document.createElement('div');
    chevron.innerHTML = `<svg style="width:14px;height:14px;color:var(--label-tertiary)" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 5l7 7-7 7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
    row.appendChild(chevron.firstChild);
    card.appendChild(row);
  }
  list.appendChild(card);
}

function showHistoryDetail(result) {
  document.getElementById('modal-history-title').textContent = result.spoolName;
  const body = document.getElementById('modal-history-body');
  body.innerHTML = '';
  body.style.padding = '16px';

  if (!result.success) {
    const errBanner = el('div', { style: { display: 'flex', alignItems: 'center', gap: '10px', padding: '12px', background: 'rgba(255,149,0,0.1)', borderRadius: '10px', marginBottom: '12px' } },
      ...parseHTML(`<svg style="width:20px;height:20px;color:var(--orange);flex-shrink:0" viewBox="0 0 24 24" fill="currentColor"><path d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>`),
      el('span', { style: { fontSize: '14px', color: 'var(--label-secondary)' } }, result.message),
    );
    body.appendChild(errBanner);
  }

  body.appendChild(renderTagDetailTable(result.payload, result.cardUid));
  showModal('modal-history');
}

// ─── Settings tab ─────────────────────────────────────────────────────────────

function initSettings() {
  const urlInput = document.getElementById('input-url');
  const displayURL = document.getElementById('display-saved-url');
  const nameStyleSel = document.getElementById('select-name-style');

  urlInput.value = Settings.baseURL;
  displayURL.textContent = Settings.baseURL;
  nameStyleSel.value = Settings.nameStyle;

  urlInput.addEventListener('input', () => {
    document.getElementById('test-logs').classList.add('hidden');
    document.getElementById('btn-save-wrap').classList.add('hidden');
  });

  document.getElementById('btn-test').addEventListener('click', async () => {
    const url = urlInput.value.trim();
    if (!url) return;
    const btn = document.getElementById('btn-test');
    btn.disabled = true;
    btn.innerHTML = `<div class="spinner white" style="width:16px;height:16px;border-width:2px"></div> Testing…`;
    const logsEl = document.getElementById('test-logs');
    logsEl.innerHTML = '';
    logsEl.classList.remove('hidden');
    document.getElementById('btn-save-wrap').classList.add('hidden');

    const result = await SpoolmanAPI.testConnection(url);
    btn.disabled = false;
    btn.innerHTML = `<svg class="btn-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9" stroke-linecap="round" stroke-linejoin="round"/> </svg> Test Connection`;

    for (const line of result.logs) {
      const cls = line.startsWith('✓') ? 'success' : line.startsWith('✗') ? 'error' : '';
      logsEl.appendChild(el('div', { class: `log-line ${cls}` }, line));
    }

    if (!result.error) {
      document.getElementById('btn-save-wrap').classList.remove('hidden');
    }
  });

  document.getElementById('btn-save-url').addEventListener('click', () => {
    const url = urlInput.value.trim();
    Settings.baseURL = url;
    api.setBaseURL(url);
    displayURL.textContent = url;
    document.getElementById('test-logs').classList.add('hidden');
    document.getElementById('btn-save-wrap').classList.add('hidden');
    showToast('URL saved', `<svg style="width:16px;height:16px;color:var(--green)" viewBox="0 0 24 24" fill="currentColor"><path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`);
  });

  nameStyleSel.addEventListener('change', () => {
    Settings.nameStyle = nameStyleSel.value;
  });

  document.getElementById('nav-brands').addEventListener('click', () => showPresetEditor('Brands', 'brands'));
  document.getElementById('nav-materials').addEventListener('click', () => showPresetEditor('Materials', 'materials'));
  document.getElementById('nav-variants').addEventListener('click', () => showPresetEditor('Variants', 'variants'));
  document.getElementById('nav-weights').addEventListener('click', () => showPresetEditor('Weights', 'weights'));
}

function showPresetEditor(title, key) {
  document.getElementById('modal-preset-editor-title').textContent = title;
  const body = document.getElementById('modal-preset-editor-body');
  renderPresetEditor(body, key);
  document.getElementById('modal-preset-editor-back').onclick = () => hideModal('modal-preset-editor');
  showModal('modal-preset-editor');
}

function renderPresetEditor(body, key) {
  body.innerHTML = '';
  const presets = Settings.presets;
  const items = presets[key] ?? [];

  const listWrap = el('div', { class: 'preset-editor-list', style: { margin: '16px 16px 0' } });

  const refresh = () => {
    listWrap.innerHTML = '';
    const current = Settings.presets[key] ?? [];
    for (let i = 0; i < current.length; i++) {
      const item = current[i];
      const row = el('div', { class: 'preset-editor-item' },
        el('span', { style: { flex: '1' } }, item),
        el('button', { class: 'remove-btn', onclick: () => {
          const p = Settings.presets;
          p[key].splice(p[key].indexOf(item), 1);
          Settings.presets = p;
          refresh();
        } }, '−'),
      );
      listWrap.appendChild(row);
    }

    let newVal = '';
    const addInput = el('input', { type: 'text', class: 'preset-add-input', placeholder: `Add ${key.slice(0, -1)}…`, autocorrect: 'off' });
    addInput.addEventListener('input', e => { newVal = e.target.value; });
    const addBtn = el('button', { class: 'preset-add-btn', onclick: () => {
      const trimmed = addInput.value.trim();
      if (!trimmed) return;
      const p = Settings.presets;
      const existing = (p[key] ?? []).map(s => s.toLowerCase());
      if (!existing.includes(trimmed.toLowerCase())) {
        p[key] = [...(p[key] ?? []), trimmed];
        Settings.presets = p;
      }
      addInput.value = '';
      refresh();
    } }, '+');
    addInput.addEventListener('keydown', e => { if (e.key === 'Enter') addBtn.click(); });
    listWrap.appendChild(el('div', { class: 'preset-add-row' }, addInput, addBtn));
  };

  refresh();
  body.appendChild(listWrap);

  const spoolBrands = [...new Set(state.spools.map(s => s.filament?.vendor?.name).filter(Boolean))].sort();
  const spoolMaterials = [...new Set(state.spools.map(s => s.filament?.material).filter(Boolean))].sort();
  const spoolMap = { brands: spoolBrands, materials: spoolMaterials, variants: [] };
  const suggestions = (spoolMap[key] ?? []).filter(s => {
    const p = Settings.presets;
    return !(p[key] ?? []).map(x => x.toLowerCase()).includes(s.toLowerCase());
  });

  if (suggestions.length > 0) {
    body.appendChild(el('div', { class: 'spoolman-suggestions-header' }, 'From Spoolman'));
    const suggestWrap = el('div', { style: { margin: '0 16px', background: 'var(--bg-card-solid)', borderRadius: '12px', border: '1px solid var(--separator)', overflow: 'hidden' } });
    for (const s of suggestions) {
      const row = el('div', { class: 'suggestion-item', onclick: () => {
        const p = Settings.presets;
        const existing = (p[key] ?? []).map(x => x.toLowerCase());
        if (!existing.includes(s.toLowerCase())) {
          p[key] = [...(p[key] ?? []), s];
          Settings.presets = p;
          renderPresetEditor(body, key);
        }
      } },
        el('span', {}, s),
        el('span', { class: 'plus' }, '+'),
      );
      suggestWrap.appendChild(row);
    }
    body.appendChild(suggestWrap);
  }
}

// ─── Sort menu ────────────────────────────────────────────────────────────────

function showSortMenu() {
  const menu = document.getElementById('sort-menu');
  menu.querySelectorAll('.sort-item').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.sort === state.sortBy);
    btn.onclick = () => {
      if (state.sortBy === btn.dataset.sort) {
        state.sortAscending = !state.sortAscending;
      } else {
        state.sortBy = btn.dataset.sort;
        state.sortAscending = true;
      }
      localStorage.setItem('spoolsSortBy', state.sortBy);
      localStorage.setItem('spoolsSortAscending', state.sortAscending);
      document.getElementById('modal-overlay').classList.add('hidden');
      menu.classList.add('hidden');
      renderSpools();
    };
  });
  document.getElementById('modal-overlay').classList.remove('hidden');
  menu.classList.remove('hidden');
}

// ─── Tab switching ────────────────────────────────────────────────────────────

function switchTab(tab) {
  state.activeTab = tab;
  document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(`tab-${tab}`)?.classList.add('active');
  document.querySelector(`.tab-btn[data-tab="${tab}"]`)?.classList.add('active');

  if (tab === 'spools') ensureSpoolsLoaded();
  if (tab === 'history') renderHistory();
  if (tab === 'scan') ensureSpoolsLoaded();
}

// ─── Init ─────────────────────────────────────────────────────────────────────

function init() {
  // Tab bar
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.dataset.tab));
  });

  // Scan tab
  document.getElementById('btn-scan').addEventListener('click', () => {
    if (state.isScanning) {
      stopNFC();
      setScanningUI(false);
      updateStatus('Scanning stopped');
    } else if (!state.nfcSupported) {
      showToast('NFC not supported in this browser');
    } else {
      state.lastResult = null;
      document.getElementById('scan-result').classList.add('hidden');
      document.getElementById('scan-result').innerHTML = '';
      setScanningUI(true);
      updateStatus('Hold your NFC tag near the device…');
      startNFC();
    }
  });

  if (!state.nfcSupported) {
    const scanContent = document.querySelector('#tab-scan .scroll-content');
    const banner = el('div', { class: 'nfc-unsupported' }, 'NFC scanning requires Chrome on Android. Other features work on all platforms.');
    scanContent.insertBefore(banner, scanContent.children[2]);
  }

  // Spools tab
  document.getElementById('btn-refresh-spools').addEventListener('click', () => fetchSpools(true));
  document.getElementById('btn-sort-spools').addEventListener('click', showSortMenu);

  // History tab
  document.getElementById('btn-clear-history').addEventListener('click', () => {
    showConfirm('Clear History', 'Remove all scan history?', 'Clear All', () => {
      state.scanHistory = [];
      state.lastResult = null;
      updateHistoryBadge();
      renderHistory();
    });
  });

  // Modal closes
  document.getElementById('modal-spool-close').addEventListener('click', () => hideModal('modal-spool'));
  document.getElementById('modal-assign-cancel').addEventListener('click', () => hideModal('modal-assign'));
  document.getElementById('modal-create-cancel').addEventListener('click', () => hideModal('modal-create'));
  document.getElementById('modal-history-close').addEventListener('click', () => hideModal('modal-history'));
  document.getElementById('modal-preset-editor-back').addEventListener('click', () => hideModal('modal-preset-editor'));

  // Modal overlay closes sort menu and modals
  document.getElementById('modal-overlay').addEventListener('click', () => {
    const sortMenu = document.getElementById('sort-menu');
    if (!sortMenu.classList.contains('hidden')) {
      sortMenu.classList.add('hidden');
      document.getElementById('modal-overlay').classList.add('hidden');
    }
  });

  // Color picker sync
  document.getElementById('create-color-picker').addEventListener('input', e => {
    const hex = e.target.value.slice(1).toUpperCase();
    document.getElementById('create-color-hex').value = hex;
  });

  document.getElementById('create-color-hex').addEventListener('input', e => {
    const hex = e.target.value.replace(/[^0-9A-Fa-f]/g, '').toUpperCase().slice(0, 6);
    e.target.value = hex;
    if (hex.length === 6) document.getElementById('create-color-picker').value = `#${hex}`;
  });

  // Material auto-temperatures
  document.getElementById('create-material').addEventListener('input', e => {
    applyMaterialTemps(e.target.value);
  });


  initSettings();
  renderSpools();
}

init();
