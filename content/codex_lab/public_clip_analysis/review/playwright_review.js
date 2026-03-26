const fs = require('fs');
const { chromium } = require('playwright-core');

async function main() {
  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });

  const page = await browser.newPage({ viewport: { width: 1440, height: 1400 } });
  await page.goto('http://127.0.0.1:8765/viewer.html', { waitUntil: 'networkidle' });
  const primarySelector = '#video';
  const figureSelector = 'img[alt="Bowler figure only verification frame"]';
  const poseSelector = 'img[alt="Pose only verification frame"]';
  const braceSelector = 'img[alt="Brace focus verification frame"]';

  const state = await page.evaluate(async () => {
    const video = document.querySelector('#video');
    if (!video) {
      return { found: false };
    }
    video.playbackRate = 0.25;
    try {
      await video.play();
    } catch (err) {
      return {
        found: true,
        played: false,
        error: String(err),
        readyState: video.readyState,
        currentSrc: video.currentSrc,
      };
    }
    await new Promise((resolve) => setTimeout(resolve, 1500));
    return {
      found: true,
      played: true,
      paused: video.paused,
      readyState: video.readyState,
      currentTime: video.currentTime,
      duration: video.duration,
      currentSrc: video.currentSrc,
      width: video.videoWidth,
      height: video.videoHeight,
      error: video.error ? { code: video.error.code, message: video.error.message || '' } : null,
    };
  });

  const outputDir = '/Users/kanarupan/workspace/wellbowled.ai/content/codex_lab/public_clip_analysis/output/nets_release_window/playwright_checks';
  fs.mkdirSync(outputDir, { recursive: true });
  await page.locator(primarySelector).screenshot({
    path: `${outputDir}/player_start.png`,
  });

  const checkpoints = [
    ['intro', 0.2],
    ['load', 1.6],
    ['release', 4.2],
    ['freeze', 7.0],
    ['end', 10.0],
  ];
  for (const [label, time] of checkpoints) {
    const dataUrl = await page.evaluate(async (targetTime) => {
      const video = document.querySelector('#video');
      video.pause();
      if (Math.abs(video.currentTime - targetTime) > 0.02) {
        await new Promise((resolve) => {
          const onSeeked = () => {
            video.removeEventListener('seeked', onSeeked);
            resolve();
          };
          video.addEventListener('seeked', onSeeked);
          video.currentTime = targetTime;
        });
      }
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      return canvas.toDataURL('image/png');
    }, time);
    const png = dataUrl.replace(/^data:image\/png;base64,/, '');
    fs.writeFileSync(`${outputDir}/${label}.png`, Buffer.from(png, 'base64'));
  }

  await page.locator(figureSelector).screenshot({
    path: `${outputDir}/viewer_figure_panel.png`,
  });
  await page.locator(poseSelector).screenshot({
    path: `${outputDir}/viewer_pose_panel.png`,
  });
  await page.locator(braceSelector).screenshot({
    path: `${outputDir}/viewer_brace_panel.png`,
  });

  await page.screenshot({
    path: `${outputDir}/viewer_full.png`,
    fullPage: true,
  });

  console.log(JSON.stringify(state, null, 2));
  await browser.close();
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
