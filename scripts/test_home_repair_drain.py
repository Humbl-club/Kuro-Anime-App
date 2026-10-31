#!/usr/bin/env python3
"""Compile actual Home/SQLite owners on macOS; injected transport, never hosted/iOS proof.

Uses a separate temporary module directory so a compiler update cannot reuse old ABI files.
No credentials, network, Xcode license acceptance, simulator or repository build deletion.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = Path('/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin')
SDK = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'

def main():
    with tempfile.TemporaryDirectory(prefix='kuro-home-drain-') as directory:
        build = Path(directory)
        common = [str(TOOLCHAIN/'swiftc'), '-swift-version', '5', '-package-name', 'KuroModules',
                  '-sdk', SDK, '-I', str(build), '-L', str(build)]
        for package in ('KuroCore', 'KuroLibrary'):
            command = common + ['-parse-as-library', '-emit-module', '-emit-library', '-module-name', package,
                                '-emit-module-path', str(build/(package+'.swiftmodule')),
                                '-o', str(build/('lib'+package+'.dylib'))]
            command += [str(p) for p in sorted((ROOT/'Packages/KuroModules/Sources'/package).glob('*.swift'))]
            if package == 'KuroLibrary':
                command += ['-lKuroCore']
            subprocess.run(command, cwd=ROOT, check=True)
        # Regression: new numeric unit cursors must survive decode/encode exactly.
        wire_source = build/'WireRepro.swift'
        wire_source.write_text(r'''import Foundation
@main struct WireRepro {
 static func main() throws {
  let text = "9007199254740992.123456789012345678901"
  let cursor = try JSONDecoder().decode(SeriesUnitPage.Cursor.self,
   from: Data(("{\"order\":\""+text+"\",\"id\":\"u\"}").utf8))
  let body = try JSONEncoder().encode(RPCSeriesUnitPage(p_medium:"manga",p_media_id:1,
   p_section_id:nil,p_edition_key:"official",p_after_order:cursor.order,p_after_id:cursor.id))
  let object = try JSONSerialization.jsonObject(with:body) as! [String:Any]
  precondition(object["p_after_order"] as? String == text,"Unit paging cursor lost database precision")
  let unit = try JSONDecoder().decode(SeriesDetailBundle.Unit.self,
   from: Data(("{\"id\":\"u\",\"label\":\"2.5\",\"order_key\":\""+text+"\",\"available\":true,\"edition_key\":\"official\"}").utf8))
  precondition(unit.exactOrderKey == text && unit.label == "2.5")
  let legacy = try JSONDecoder().decode(SeriesDetailBundle.Unit.self,
   from: Data(#"{"id":"u","label":"1","order_key":1,"available":true,"edition_key":""}"#.utf8))
  precondition(legacy.orderKey == 1)
  print("UNIT_CURSOR_PRECISION_AND_LEGACY_DECODE: PASS")
 }
}
''')
        wire_executable = build/'WireRepro'
        subprocess.run(common + ['-parse-as-library', '-o', str(wire_executable),
            'Kuro/Home/HomeContracts.swift', str(wire_source)], cwd=ROOT, check=True)
        subprocess.run([str(wire_executable)], cwd=ROOT, check=True)
        executable = build/'HomeDrain'
        # Only presentation error copy is stubbed; all state, leases, SQLite and drain
        # code is compiled verbatim from the current checkout (no SDK/iOS here).
        (build/'ErrorCopy.swift').write_text('import KuroLibrary\n@MainActor enum LibraryActions { static func libraryErrorDescription(_ error: LibraryError) -> String { String(describing:error) } }\n')
        subprocess.run(common + ['-parse-as-library', '-lKuroCore', '-lKuroLibrary', '-o', str(executable),
            'Kuro/Composition/AccountScopedState.swift', 'Kuro/Catalog/MissingSupabaseConfiguration.swift',
            'Kuro/Home/HomeContracts.swift', 'Kuro/Home/HomePersonalSnapshot.swift', 'Kuro/Home/HomeStore.swift',
            str(build/'ErrorCopy.swift'),
            'docs/handoffs/2026-10-07-home-series-evidence/repairs/HomeRepairRepro.swift'], cwd=ROOT, check=True)
        subprocess.run([str(executable)], cwd=ROOT, check=True,
                       env={**os.environ, 'DYLD_LIBRARY_PATH':str(build)})

if __name__ == '__main__':
    main()
