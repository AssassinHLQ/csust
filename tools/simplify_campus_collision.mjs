// Use meshoptimizer's absolute geometric error to reduce redundant triangles.
// Usage: node tools/simplify_campus_collision.mjs <runtime> <prefix> <error_m>
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [runtime, prefix, errorText = '0.05'] = process.argv.slice(2);
const { MeshoptSimplifier } = await import(pathToFileURL(path.resolve(runtime, 'node_modules/meshoptimizer/index.js')));
await MeshoptSimplifier.ready;
const read = (file, Type) => {
    const bytes = fs.readFileSync(file);
    return new Type(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
};
const vertices = read(prefix + '.vertices.f32', Float32Array);
const indices = read(prefix + '.indices.u32', Uint32Array);
const tolerance = Number(errorText);
if (!(tolerance > 0 && tolerance <= .25)) throw new Error('Expected error in (0, 0.25] metres');
const [simplified, error] = MeshoptSimplifier.simplify(
    indices, vertices, 3, 0, tolerance, ['ErrorAbsolute', 'LockBorder']
);
const faces = new Float32Array(simplified.length * 3);
for (let i = 0; i < simplified.length; i++) {
    const source = simplified[i] * 3;
    faces[i * 3] = vertices[source];
    faces[i * 3 + 1] = vertices[source + 1];
    faces[i * 3 + 2] = vertices[source + 2];
}
fs.writeFileSync(prefix + '.faces.f32', new Uint8Array(faces.buffer));
const report = {
    original_triangles: indices.length / 3,
    simplified_triangles: simplified.length / 3,
    tolerance_m: tolerance,
    approximate_error_m: error,
    note: 'meshoptimizer approximate geometric error; validate gameplay separately'
};
fs.writeFileSync(prefix + '.simplification.json', JSON.stringify(report, null, 2));
console.log(report);
