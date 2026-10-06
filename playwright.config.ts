import { defineConfig } from '@playwright/test';
import { existsSync } from 'node:fs';

// Prefer a locally provided Chromium (e.g. CI images that preinstall one) so
// `npx playwright install` is not required. Falls back to Playwright's own
// managed browser when the path is absent.
const localChromium =
  process.env.PW_CHROMIUM_PATH ??
  (existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);

export default defineConfig({
  testDir: './e2e',
  timeout: 90_000,
  retries: 0,
  reporter: 'list',
  use: {
    baseURL: 'http://127.0.0.1:4173',
    headless: true,
    viewport: { width: 1280, height: 720 },
    launchOptions: localChromium ? { executablePath: localChromium } : {},
  },
  webServer: {
    command: 'npm run preview',
    url: 'http://127.0.0.1:4173',
    reuseExistingServer: false,
    timeout: 60_000,
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
