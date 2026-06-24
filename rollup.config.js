import nodeResolve from '@rollup/plugin-node-resolve';

// Build split (intentional):
//   - tsc emits the ESM build + .d.ts to dist/esm  (package.json "module" / exports.import)
//   - Rollup bundles ONLY the CJS artifact          (package.json "main"   / exports.require)
export default {
  input: 'dist/esm/index.js',
  output: {
    file: 'dist/plugin.cjs.js',
    format: 'cjs',
    sourcemap: true,
    inlineDynamicImports: true,
  },
  external: ['@capacitor/core'],
  plugins: [nodeResolve()],
};
