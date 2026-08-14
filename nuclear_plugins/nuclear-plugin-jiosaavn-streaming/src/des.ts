// DES-ECB decrypt (PKCS5 unpad) for JioSaavn media URLs
// Port of the public-domain des.js (indutny) DES implementation, trimmed to
// single-block-ECB decryption only.

function readUInt32BE(bytes: Uint8Array, off: number): number {
  return (((bytes[off] << 24) | (bytes[off + 1] << 16) | (bytes[off + 2] << 8) | bytes[off + 3]) >>> 0);
}

function writeUInt32BE(bytes: Uint8Array, value: number, off: number): void {
  bytes[off] = value >>> 24;
  bytes[off + 1] = (value >>> 16) & 0xff;
  bytes[off + 2] = (value >>> 8) & 0xff;
  bytes[off + 3] = value & 0xff;
}

function ip(inL: number, inR: number): [number, number] {
  let outL = 0;
  let outR = 0;
  for (let i = 6; i >= 0; i -= 2) {
    for (let j = 0; j <= 24; j += 8) {
      outL = (outL << 1) | ((inR >>> (j + i)) & 1);
    }
    for (let j = 0; j <= 24; j += 8) {
      outL = (outL << 1) | ((inL >>> (j + i)) & 1);
    }
  }
  for (let i = 6; i >= 0; i -= 2) {
    for (let j = 1; j <= 25; j += 8) {
      outR = (outR << 1) | ((inR >>> (j + i)) & 1);
    }
    for (let j = 1; j <= 25; j += 8) {
      outR = (outR << 1) | ((inL >>> (j + i)) & 1);
    }
  }
  return [outL >>> 0, outR >>> 0];
}

function rip(inL: number, inR: number): [number, number] {
  let outL = 0;
  let outR = 0;
  for (let i = 0; i < 4; i++) {
    for (let j = 24; j >= 0; j -= 8) {
      outL = (outL << 1) | ((inR >>> (j + i)) & 1);
      outL = (outL << 1) | ((inL >>> (j + i)) & 1);
    }
  }
  for (let i = 4; i < 8; i++) {
    for (let j = 24; j >= 0; j -= 8) {
      outR = (outR << 1) | ((inR >>> (j + i)) & 1);
      outR = (outR << 1) | ((inL >>> (j + i)) & 1);
    }
  }
  return [outL >>> 0, outR >>> 0];
}

function pc1(inL: number, inR: number): [number, number] {
  let outL = 0;
  let outR = 0;
  let i: number;
  for (i = 7; i >= 5; i--) {
    for (let j = 0; j <= 24; j += 8) {
      outL = (outL << 1) | ((inR >> (j + i)) & 1);
    }
    for (let j = 0; j <= 24; j += 8) {
      outL = (outL << 1) | ((inL >> (j + i)) & 1);
    }
  }
  for (let j = 0; j <= 24; j += 8) {
    outL = (outL << 1) | ((inR >> (j + i)) & 1);
  }
  for (i = 1; i <= 3; i++) {
    for (let j = 0; j <= 24; j += 8) {
      outR = (outR << 1) | ((inR >> (j + i)) & 1);
    }
    for (let j = 0; j <= 24; j += 8) {
      outR = (outR << 1) | ((inL >> (j + i)) & 1);
    }
  }
  for (let j = 0; j <= 24; j += 8) {
    outR = (outR << 1) | ((inL >> (j + i)) & 1);
  }
  return [outL >>> 0, outR >>> 0];
}

function r28shl(num: number, shift: number): number {
  return ((num << shift) & 0xfffffff) | (num >>> (28 - shift));
}

const pc2table = [
  14, 11, 17, 4, 27, 23, 25, 0,
  13, 22, 7, 18, 5, 9, 16, 24,
  2, 20, 12, 21, 1, 8, 15, 26,
  15, 4, 25, 19, 9, 1, 26, 16,
  5, 11, 23, 8, 12, 7, 17, 0,
  22, 3, 10, 14, 6, 20, 27, 24,
];

function pc2(inL: number, inR: number): [number, number] {
  let outL = 0;
  let outR = 0;
  const len = pc2table.length >>> 1;
  for (let i = 0; i < len; i++) {
    outL = (outL << 1) | ((inL >>> pc2table[i]) & 1);
  }
  for (let i = len; i < pc2table.length; i++) {
    outR = (outR << 1) | ((inR >>> pc2table[i]) & 1);
  }
  return [outL >>> 0, outR >>> 0];
}

function expand(r: number): [number, number] {
  let outL = 0;
  let outR = 0;
  outL = ((r & 1) << 5) | (r >>> 27);
  for (let i = 23; i >= 15; i -= 4) {
    outL = (outL << 6) | ((r >>> i) & 0x3f);
  }
  for (let i = 11; i >= 3; i -= 4) {
    outR = (outR | ((r >>> i) & 0x3f)) << 6;
  }
  outR |= ((r & 0x1f) << 1) | (r >>> 31);
  return [outL >>> 0, outR >>> 0];
}

const sTable = [
  14, 0, 4, 15, 13, 7, 1, 4, 2, 14, 15, 2, 11, 13, 8, 1,
  3, 10, 10, 6, 6, 12, 12, 11, 5, 9, 9, 5, 0, 3, 7, 8,
  4, 15, 1, 12, 14, 8, 8, 2, 13, 4, 6, 9, 2, 1, 11, 7,
  15, 5, 12, 11, 9, 3, 7, 14, 3, 10, 10, 0, 5, 6, 0, 13,

  15, 3, 1, 13, 8, 4, 14, 7, 6, 15, 11, 2, 3, 8, 4, 14,
  9, 12, 7, 0, 2, 1, 13, 10, 12, 6, 0, 9, 5, 11, 10, 5,
  0, 13, 14, 8, 7, 10, 11, 1, 10, 3, 4, 15, 13, 4, 1, 2,
  5, 11, 8, 6, 12, 7, 6, 12, 9, 0, 3, 5, 2, 14, 15, 9,

  10, 13, 0, 7, 9, 0, 14, 9, 6, 3, 3, 4, 15, 6, 5, 10,
  1, 2, 13, 8, 12, 5, 7, 14, 11, 12, 4, 11, 2, 15, 8, 1,
  13, 1, 6, 10, 4, 13, 9, 0, 8, 6, 15, 9, 3, 8, 0, 7,
  11, 4, 1, 15, 2, 14, 12, 3, 5, 11, 10, 5, 14, 2, 7, 12,

  7, 13, 13, 8, 14, 11, 3, 5, 0, 6, 6, 15, 9, 0, 10, 3,
  1, 4, 2, 7, 8, 2, 5, 12, 11, 1, 12, 10, 4, 14, 15, 9,
  10, 3, 6, 15, 9, 0, 0, 6, 12, 10, 11, 1, 7, 13, 13, 8,
  15, 9, 1, 4, 3, 5, 14, 11, 5, 12, 2, 7, 8, 2, 4, 14,

  2, 14, 12, 11, 4, 2, 1, 12, 7, 4, 10, 7, 11, 13, 6, 1,
  8, 5, 5, 0, 3, 15, 15, 10, 13, 3, 0, 9, 14, 8, 9, 6,
  4, 11, 2, 8, 1, 12, 11, 7, 10, 1, 13, 14, 7, 2, 8, 13,
  15, 6, 9, 15, 12, 0, 5, 9, 6, 10, 3, 4, 0, 5, 14, 3,

  12, 10, 1, 15, 10, 4, 15, 2, 9, 7, 2, 12, 6, 9, 8, 5,
  0, 6, 13, 1, 3, 13, 4, 14, 14, 0, 7, 11, 5, 3, 11, 8,
  9, 4, 14, 3, 15, 2, 5, 12, 2, 9, 8, 5, 12, 15, 3, 10,
  7, 11, 0, 14, 4, 1, 10, 7, 1, 6, 13, 0, 11, 8, 6, 13,

  4, 13, 11, 0, 2, 11, 14, 7, 15, 4, 0, 9, 8, 1, 13, 10,
  3, 14, 12, 3, 9, 5, 7, 12, 5, 2, 10, 15, 6, 8, 1, 6,
  1, 6, 4, 11, 11, 13, 13, 8, 12, 1, 3, 4, 7, 10, 14, 7,
  10, 9, 15, 5, 6, 0, 8, 15, 0, 14, 5, 2, 9, 3, 2, 12,

  13, 1, 2, 15, 8, 13, 4, 8, 6, 10, 15, 3, 11, 7, 1, 4,
  10, 12, 9, 5, 3, 6, 14, 11, 5, 0, 0, 14, 12, 9, 7, 2,
  7, 2, 11, 1, 4, 14, 1, 7, 9, 4, 12, 10, 14, 8, 2, 13,
  0, 15, 6, 12, 10, 9, 13, 0, 15, 3, 3, 5, 5, 6, 8, 11,
];

function substitute(inL: number, inR: number): number {
  let out = 0;
  for (let i = 0; i < 4; i++) {
    const b = (inL >>> (18 - i * 6)) & 0x3f;
    const sb = sTable[i * 0x40 + b];
    out = (out << 4) | sb;
  }
  for (let i = 0; i < 4; i++) {
    const b = (inR >>> (18 - i * 6)) & 0x3f;
    const sb = sTable[4 * 0x40 + i * 0x40 + b];
    out = (out << 4) | sb;
  }
  return out >>> 0;
}

const permuteTable = [
  16, 25, 12, 11, 3, 20, 4, 15, 31, 17, 9, 6, 27, 14, 1, 22,
  30, 24, 8, 18, 0, 5, 29, 23, 13, 19, 2, 26, 10, 21, 28, 7,
];

function permute(num: number): number {
  let out = 0;
  for (let i = 0; i < permuteTable.length; i++) {
    out = (out << 1) | ((num >>> permuteTable[i]) & 1);
  }
  return out >>> 0;
}

const shiftTable = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

export function deriveKeys(key: Uint8Array): number[] {
  const keys = new Array<number>(16 * 2);
  let kL = readUInt32BE(key, 0);
  let kR = readUInt32BE(key, 4);
  [kL, kR] = pc1(kL, kR);
  for (let i = 0; i < keys.length; i += 2) {
    const shift = shiftTable[i >>> 1];
    kL = r28shl(kL, shift);
    kR = r28shl(kR, shift);
    const [oL, oR] = pc2(kL, kR);
    keys[i] = oL;
    keys[i + 1] = oR;
  }
  return keys;
}

function desDecryptBlock(keys: number[], lStart: number, rStart: number): [number, number] {
  let l = rStart;
  let r = lStart;
  for (let i = keys.length - 2; i >= 0; i -= 2) {
    const keyL = keys[i];
    const keyR = keys[i + 1];
    const [eL, eR] = expand(l);
    const s = substitute(keyL ^ eL, keyR ^ eR);
    const f = permute(s);
    const t = l;
    l = (r ^ f) >>> 0;
    r = t;
  }
  return [l, r];
}

export function decryptDesEcb(ciphertext: Uint8Array, key: Uint8Array): Uint8Array {
  const keys = deriveKeys(key);
  const out = new Uint8Array(ciphertext.length);
  for (let off = 0; off < ciphertext.length; off += 8) {
    let l = readUInt32BE(ciphertext, off);
    let r = readUInt32BE(ciphertext, off + 4);
    [l, r] = ip(l, r);
    [l, r] = desDecryptBlock(keys, l, r);
    [l, r] = rip(l, r);
    writeUInt32BE(out, l, off);
    writeUInt32BE(out, r, off + 4);
  }
  const pad = out[out.length - 1];
  if (pad >= 1 && pad <= 8) {
    let valid = true;
    for (let i = out.length - pad; i < out.length; i++) {
      if (out[i] !== pad) {
        valid = false;
        break;
      }
    }
    if (valid) {
      return out.slice(0, out.length - pad);
    }
  }
  return out;
}
