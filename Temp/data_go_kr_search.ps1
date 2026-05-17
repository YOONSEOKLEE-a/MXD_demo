$script = @'
const { chromium } = require('D:/MPC_Korea_dual_track/node_modules/playwright');
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const context = browser.contexts()[0];
  const page = context.pages()[0] || await context.newPage();
  const keywords = ['시간별 전력사용량 건물', '전력사용량 시간별 시설', '홈에너지 시간별 사용', '상권 에너지 사용량', '시간별 계량데이터 전력', '건물 에너지 사용량 전력 시간별'];
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
'@
$tmp = 'D:\Temp\data_go_kr_search.js'
Set-Content -Path $tmp -Value $script -Encoding UTF8
& 'C:\Program Files\nodejs\node.exe' $tmp
