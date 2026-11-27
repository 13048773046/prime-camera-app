import asyncio, sys
from playwright.async_api import async_playwright
out = sys.argv[1] if len(sys.argv)>1 else 'analysis/preview.png'
wait = int(sys.argv[2]) if len(sys.argv)>2 else 7000
async def main():
  async with async_playwright() as p:
    b = await p.chromium.launch(executable_path='/usr/local/bin/chromium')
    pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2)
    await pg.goto('http://127.0.0.1:8099', wait_until='networkidle')
    await pg.wait_for_timeout(wait)
    await pg.screenshot(path=out)
    await b.close()
asyncio.run(main())
