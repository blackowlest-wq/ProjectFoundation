import { runFrontendLint } from '../eslint-rules/index.mjs';

const result = await runFrontendLint({
  cwd: process.cwd(),
  args: process.argv.slice(2),
});

if (result.stdout) {
  process.stdout.write(result.stdout);
}
if (result.stderr) {
  process.stderr.write(result.stderr);
}
process.exitCode = result.exitCode;
