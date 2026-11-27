import asyncio, sys
from playwright.async_api import async_playwright
action = sys.argv[1]
out = sys.argv[2]
async def main():
  async with async_playwright() as p:
    b = await p.chromium.launch(executable_path='/usr/local/bin/chromium')
    pg = await b.new_page(viewport={'width':390,'height':844}, device_scale_factor=2)
    await pg.goto('http://127.0.0.1:8099', wait_until='networkidle')
    await pg.wait_for_timeout(900)
    if action == 'gallery':
      await pg.mouse.click(195, 756)
    elif action == 'filter':
      await pg.mouse.click(62, 596)
    elif action == 'mine':
      await pg.mouse.click(300, 756)
    await pg.wait_for_timeout(700)
    await pg.screenshot(path=out)
    await b.close()
asyncio.run(main())
