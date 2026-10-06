import { expect, test } from '@playwright/test';

test('pipeline: page loads and draws to canvas', async ({ page }) => {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto('/');
  await page.waitForFunction(() => (window as unknown as { __pipelineOk?: boolean }).__pipelineOk === true);
  expect(errors).toEqual([]);
});
