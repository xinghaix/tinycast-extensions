import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  NIL_UUID,
  MAX_UUID,
  UUID_NAMESPACES,
  generateUuidV1,
  generateUuidV3,
  generateUuidV4,
  generateUuidV5,
  generateUuidV6,
  generateUuidV7,
  generateUuidV8,
  generateUlid,
  generateNanoId,
  generateKsuid,
  generateObjectId,
  formatUuidVariants,
  inspectIdentifier,
} from "../src/uuid.ts";
import { parseTimestampInput, buildTimestampReport } from "../src/timestamp.ts";
import { sm3, computeHashes, decodeHashInput, matchesExpectedHash } from "../src/hash.ts";
import {
  encodeBase32,
  decodeBase32,
  encodeBase58,
  decodeBase58,
  encodeHtmlEntities,
  decodeHtmlEntities,
  encodeUnicodeEscapes,
  decodeUnicodeEscapes,
  encodeMorse,
  decodeMorse,
  decodeJwt,
  verifyJwtHmac,
  runAllCodecs,
  encryptAes,
  decryptAes,
} from "../src/codec.ts";
import { analyzeJson, jsonToTypeScript, jsonToYaml } from "../src/json-tools.ts";
import { toCamelCase, toSnakeCase, toKebabCase, toPascalCase, toConstantCase, computeTextStats } from "../src/text-tools.ts";
import { generateRandomPassword, generatePassphrase } from "../src/password.ts";
import { generateQrSvg } from "../src/qr.ts";
import { parseCron } from "../src/cron.ts";
import { parseSimpleColor } from "../src/color.ts";
import { detectClipboardKind } from "../src/clipboard-detect.ts";
import { cleanPlainText, parseCaffeinateAction, parseDurationToSeconds } from "../src/system-shortcuts.ts";

describe("UUID & Modern IDs", () => {
  it("generates compliant RFC 9562 v1/v3/v4/v5/v6/v7/v8 and inspects timestamps", () => {
    const ts = 1731830400123;
    const v1 = generateUuidV1({ timestampMs: ts });
    const v3 = generateUuidV3("www.example.com", UUID_NAMESPACES.dns.uuid);
    const v4 = generateUuidV4();
    const v5 = generateUuidV5("www.example.com", UUID_NAMESPACES.dns.uuid);
    const v6 = generateUuidV6({ timestampMs: ts });
    const v7 = generateUuidV7(ts);
    const v8 = generateUuidV8("tinycast-seed");

    // Known RFC 4122 / 9562 test vectors for v3 and v5 with DNS namespace
    assert.equal(v3, "5df41881-3aed-3515-88a7-2f4a814cf09e");
    assert.equal(v5, "2ed6657d-e927-568b-95e1-2665a8aea6a2");

    assert.equal(inspectIdentifier(v1)?.version, "v1");
    assert.equal(inspectIdentifier(v1)?.timestampMs, ts);
    assert.equal(inspectIdentifier(v4)?.version, "v4");
    assert.equal(inspectIdentifier(v6)?.version, "v6");
    assert.equal(inspectIdentifier(v6)?.timestampMs, ts);
    assert.equal(inspectIdentifier(v7)?.version, "v7");
    assert.equal(inspectIdentifier(v7)?.timestampMs, ts);
    assert.equal(inspectIdentifier(v8)?.version, "v8");
    assert.equal(v8, generateUuidV8("tinycast-seed")); // deterministic with seed

    assert.equal(inspectIdentifier(NIL_UUID)?.version, "Nil (0)");
    assert.equal(inspectIdentifier(MAX_UUID)?.version, "Max (F)");
  });

  it("produces strictly monotonic v7 and ULID batches", () => {
    const v7s = Array.from({ length: 20 }, () => generateUuidV7());
    for (let i = 1; i < v7s.length; i++) {
      assert.ok(v7s[i] > v7s[i - 1], `v7[${i}] (${v7s[i]}) should be > v7[${i - 1}] (${v7s[i - 1]})`);
    }

    const ulids = Array.from({ length: 20 }, () => generateUlid());
    for (let i = 1; i < ulids.length; i++) {
      assert.ok(ulids[i] > ulids[i - 1], `ulid[${i}] should be > ulid[${i - 1}]`);
    }

    const fixedTs = 1731830400500;
    const ulid = generateUlid(fixedTs);
    assert.equal(inspectIdentifier(ulid)?.timestampMs, fixedTs);

    const ksuid = generateKsuid(1731830400000);
    assert.equal(ksuid.length, 27);
    assert.equal(inspectIdentifier(ksuid)?.timestampMs, 1731830400000);

    const oid = generateObjectId(1731830400000);
    assert.equal(oid.length, 24);
    assert.equal(inspectIdentifier(oid)?.timestampMs, 1731830400000);

    assert.equal(generateNanoId(12).length, 12);
    const variants = formatUuidVariants(v7s[0]);
    assert.equal(variants.compact.length, 32);
    assert.ok(variants.urn.startsWith("urn:uuid:"));
  });
});

describe("Timestamp Converter", () => {
  it("auto-detects s, ms, us, ns, compact dates, SQL, ISO, and relative expressions", () => {
    const now = new Date("2026-11-17T07:35:13.000Z");

    const s = parseTimestampInput("1731830400", now);
    assert.equal(s?.sourceUnit, "s");
    assert.equal(s?.date.getTime(), 1731830400000);

    const ms = parseTimestampInput("1731830400123", now);
    assert.equal(ms?.sourceUnit, "ms");
    assert.equal(ms?.date.getTime(), 1731830400123);

    const us = parseTimestampInput("1731830400123456", now);
    assert.equal(us?.sourceUnit, "us");
    assert.equal(us?.date.getTime(), 1731830400123);

    const ns = parseTimestampInput("1731830400123456789", now);
    assert.equal(ns?.sourceUnit, "ns");
    assert.equal(ns?.date.getTime(), 1731830400123);

    const rel = parseTimestampInput("+2h", now);
    assert.equal(rel?.date.getTime(), now.getTime() + 7_200_000);

    const iso = parseTimestampInput("2026-11-17T07:35:13Z", now);
    assert.equal(iso?.date.toISOString(), "2026-11-17T07:35:13.000Z");

    const compact = parseTimestampInput("20261117083000", now);
    assert.equal(compact?.date.getHours(), 8);
    assert.equal(compact?.date.getMinutes(), 30);

    const report = buildTimestampReport(iso!, now, ["Asia/Shanghai"]);
    assert.ok(report.entries.some((e) => e.id === "tz-Asia/Shanghai" && e.value === "2026-11-17 15:35:13"));
  });
});

describe("Hashing & Checksums", () => {
  it("matches official SM3 and standard hash test vectors", () => {
    // GM/T 0004-2012 standard vector: SM3("abc")
    const sm3Digest = Buffer.from(sm3(Buffer.from("abc", "utf8"))).toString("hex");
    assert.equal(sm3Digest, "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0");

    const results = computeHashes(Buffer.from("abc", "utf8"));
    const sha256 = results.find((r) => r.id === "sha256");
    assert.equal(sha256?.hexLower, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");

    const sha3 = results.find((r) => r.id === "sha3-256");
    assert.equal(sha3?.hexLower, "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532");

    const crc = results.find((r) => r.id === "crc32");
    assert.equal(crc?.hexLower, "352441c2");

    assert.ok(matchesExpectedHash(sha256!, sha256!.hexUpper));
    assert.ok(matchesExpectedHash(sha256!, sha256!.sri));

    const hmacResults = computeHashes(Buffer.from("message", "utf8"), { hmacKey: Buffer.from("secret", "utf8") });
    const hmacSha256 = hmacResults.find((r) => r.id === "sha256");
    assert.equal(hmacSha256?.hexLower, "8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b");

    assert.deepEqual(decodeHashInput("0x48656c6c6f", "hex"), Buffer.from("Hello"));
  });
});

describe("Codecs, JWT & AES", () => {
  it("round-trips Base32, Base58, HTML, Unicode, Morse, Gzip, and AES-GCM/CBC", () => {
    const sample = "你好 Tinycast 🚀 & <test>";
    const buf = Buffer.from(sample, "utf8");

    assert.equal(decodeBase32(encodeBase32(buf))?.toString("utf8"), sample);
    assert.equal(decodeBase58(encodeBase58(buf))?.toString("utf8"), sample);
    assert.equal(decodeHtmlEntities(encodeHtmlEntities(sample)), sample);
    assert.equal(decodeUnicodeEscapes(encodeUnicodeEscapes(sample, false)), sample);
    assert.equal(decodeUnicodeEscapes(encodeUnicodeEscapes(sample, true)), sample);
    assert.equal(decodeMorse(encodeMorse("HELLO WORLD")), "HELLO WORLD");

    const entries = runAllCodecs("SGVsbG8sIFdvcmxkIQ==");
    const b64 = entries.find((e) => e.id === "base64-decode");
    assert.equal(b64?.output, "Hello, World!");

    // AES-256-GCM & CBC round-trip
    const gcmCipher = encryptAes(sample, "my-strong-passphrase", "aes-256-gcm", "pbkdf2");
    assert.equal(decryptAes(gcmCipher, "my-strong-passphrase"), sample);

    const cbcCipher = encryptAes(sample, "my-strong-passphrase", "aes-256-cbc", "pbkdf2");
    assert.equal(decryptAes(cbcCipher, "my-strong-passphrase"), sample);
  });

  it("decodes and verifies HS256 JWTs", () => {
    // Header {"alg":"HS256","typ":"JWT"}, Payload {"sub":"123","name":"Ada"} signed with "secret"
    const h = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
    const p = Buffer.from(JSON.stringify({ sub: "123", name: "Ada" })).toString("base64url");
    const hmac = computeHashes(Buffer.from(`${h}.${p}`), { hmacKey: Buffer.from("secret") }).find((r) => r.id === "sha256")!.base64url;
    const token = `${h}.${p}.${hmac}`;

    const decoded = decodeJwt(token);
    assert.equal(decoded?.algorithm, "HS256");
    assert.equal(decoded?.payload.name, "Ada");
    assert.equal(verifyJwtHmac(token, "secret").valid, true);
    assert.equal(verifyJwtHmac(token, "wrong").valid, false);
  });
});

describe("JSON, Text, Password, QR, Cron & Clipboard", () => {
  it("repairs relaxed JSON and generates TS/YAML", () => {
    const analysis = analyzeJson("{ /* comment */ name: 'Tinycast', tags: ['fast', 'mac',], }");
    assert.equal(analysis.valid, true);
    assert.equal(analysis.repaired, true);
    assert.ok(analysis.tsInterface?.includes("name: string;"));
    assert.ok(analysis.yaml?.includes("name: Tinycast"));
    assert.ok(jsonToTypeScript({ id: 1 }).includes("id: number;"));
    assert.ok(jsonToYaml(["a", "b"]).includes("- a"));
  });

  it("transforms text cases and computes stats", () => {
    assert.equal(toCamelCase("hello_world_test"), "helloWorldTest");
    assert.equal(toPascalCase("hello-world-test"), "HelloWorldTest");
    assert.equal(toSnakeCase("helloWorldTest"), "hello_world_test");
    assert.equal(toConstantCase("helloWorldTest"), "HELLO_WORLD_TEST");
    assert.equal(toKebabCase("HelloWorldTest"), "hello-world-test");
    assert.equal(computeTextStats("hi 世界\nline2").lines, 2);
  });

  it("generates passwords, SVG QR codes, Cron schedules, and detects clipboard", () => {
    const pw = generateRandomPassword({ length: 20, symbols: true });
    assert.equal(pw.password.length, 20);
    assert.ok(pw.entropyBits > 100);

    const phrase = generatePassphrase(4, "-");
    assert.equal(phrase.passphrase.split("-").length, 4);

    const qr = generateQrSvg("https://github.com/abue-ammar/tinycast");
    assert.ok(qr.svg.startsWith("<svg"));
    assert.ok(qr.dataUrl.startsWith("data:image/svg+xml;base64,"));

    const cron = parseCron("*/15 9-17 * * 1-5", { from: new Date("2026-11-16T08:00:00"), count: 5 });
    assert.equal(cron.nextRuns.length, 5);
    assert.equal(cron.nextRuns[0].getHours(), 9);
    assert.equal(cron.nextRuns[0].getMinutes(), 0);

    assert.equal(detectClipboardKind(generateUuidV4()).kind, "uuid-or-id");
    assert.equal(detectClipboardKind("1731830400").kind, "timestamp");
    assert.equal(detectClipboardKind('{"a":1}').kind, "json");
    assert.equal(detectClipboardKind("#3B82F6").kind, "color");

    const col = parseSimpleColor("rgb(59, 130, 246)");
    assert.equal(col?.hexUpper, "#3B82F6");
    assert.equal(col?.hslCss, "hsl(217, 91%, 60%)");
    assert.equal(parseSimpleColor("#f0a")?.rgbCss, "rgb(255, 0, 170)");
    assert.equal(parseSimpleColor("hsl(217, 91%, 60%)")?.hexUpper, "#3C83F6");

    assert.equal(detectClipboardKind("curl -X POST https://api.example.com -H 'Accept: application/json'").kind, "curl");
    assert.equal(detectClipboardKind("10.0.12.34/22").kind, "cidr");
    assert.equal(detectClipboardKind("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP2bJ+6B8xP1n6rO8gO9kH8vQ7mZ3R4k5L1xM2nN0p devkit@test").kind, "cert");
    assert.equal(detectClipboardKind("SELECT id, name FROM users WHERE id = 1").kind, "sql");
    assert.equal(detectClipboardKind("Preparing: SELECT * FROM orders WHERE id = ?").kind, "sql");
    assert.equal(detectClipboardKind("$199.50").kind, "currency");
    assert.equal(detectClipboardKind("5000 JPY").kind, "currency");
    assert.equal(detectClipboardKind("1731830400").kind, "timestamp");
  });

  it("parses caffeinate intents and cleans plain text safely", () => {
    assert.equal(parseCaffeinateAction("").kind, "toggle");
    assert.equal(parseCaffeinateAction("off").kind, "off");
    assert.equal(parseCaffeinateAction("status").kind, "status");
    assert.deepEqual(parseCaffeinateAction("forever"), {
      kind: "on",
      durationSeconds: null,
      label: "持续保持唤醒",
    });
    assert.equal(parseDurationToSeconds("30m"), 1800);
    assert.equal(parseDurationToSeconds("1h30m"), 5400);
    assert.equal(parseDurationToSeconds("45"), 2700);
    const act = parseCaffeinateAction("2h");
    assert.equal(act.kind, "on");
    if (act.kind === "on") {
      assert.equal(act.durationSeconds, 7200);
    }

    assert.equal(cleanPlainText("\uFEFFline1\r\n  line2  \r"), "line1\n  line2  \n");
    assert.equal(cleanPlainText("  hello  \n  world  ", "trim"), "hello\nworld");
    assert.equal(cleanPlainText("  hello  \n\t world  ", "singleline"), "hello world");
  });
});
