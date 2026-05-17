const { chromium } = require('D:/MPC_Korea_dual_track/node_modules/playwright');
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const context = browser.contexts()[0];
  const page = context.pages()[0] || await context.newPage();
  const keywords = ['?쒓컙蹂??꾨젰?ъ슜??嫄대Ъ', '?꾨젰?ъ슜???쒓컙蹂??쒖꽕', '?덉뿉?덉? ?쒓컙蹂??ъ슜', '?곴텒 ?먮꼫吏 ?ъ슜??, '?쒓컙蹂?怨꾨웾?곗씠???꾨젰', '嫄대Ъ ?먮꼫吏 ?ъ슜???꾨젰 ?쒓컙蹂?];
  for (const keyword of keywords) {
    const url = 'https://www.data.go.kr/tcs/dss/selectDataSetList.do?keyword=' + encodeURIComponent(keyword);
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1500);
    const items = await page.evaluate(() => {
      const anchors = Array.from(document.querySelectorAll('a[href*="/data/"]'));
      return anchors.map(a => ({ text: (a.textContent || '').trim().replace(/\s+/g, ' '), href: a.href }))
        .filter(item => item.text && item.href.includes('/data/'));
    });
    const seen = new Set();
    console.log('\nKEYWORD:', keyword);
    for (const item of items) {
      if (seen.has(item.href)) continue;
      seen.add(item.href);
      console.log('-', item.text, '|', item.href);
      if (seen.size >= 10) break;
    }
  }
  process.exit(0);
})().catch(err => { console.error(err); process.exit(1); });
