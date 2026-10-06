// Placeholder entry point used only to validate the build pipeline.
// Replaced by the real game bootstrap during implementation.
const canvas = document.getElementById('game') as HTMLCanvasElement | null;
const ctx = canvas?.getContext('2d');
if (ctx) {
  ctx.fillStyle = '#0b0e17';
  ctx.fillRect(0, 0, 1920, 1080);
  ctx.fillStyle = '#ffffff';
  ctx.font = '64px system-ui';
  ctx.fillText('pipeline ok', 100, 200);
}
(window as unknown as { __pipelineOk: boolean }).__pipelineOk = true;
