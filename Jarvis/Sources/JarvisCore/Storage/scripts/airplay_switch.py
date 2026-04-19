#!/usr/bin/env python3
"""Switch AirPlay 2 input using pyatv Library."""
import sys
import asyncio
from pyatv import scan, connect

async def switch_app(host, app_name):
    devices = await scan(hosts=[host])
    if not devices:
        print(f"No AirPlay device found at {host}", file=sys.stderr)
        sys.exit(1)

    atv = devices[0]
    async with connect(atv) as app:
        if hasattr(app, 'launch_app'):
            await app.launch_app(app_name)
        print(f"Switched to {app_name} on {atv.name}")

if __name__ == '__main__':
    asyncio.run(switch_app(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Jarvis"))
