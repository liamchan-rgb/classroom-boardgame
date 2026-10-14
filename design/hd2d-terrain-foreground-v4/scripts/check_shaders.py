"""Static GLES fragment validation with SpriteKit's documented inputs declared."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = (Path(__file__).resolve().parents[1]/'Native/Sources/HD2DRenderer.swift').read_text()
validator = sys.argv[1] if len(sys.argv)>1 else 'glslangValidator'
for name in ('surfaceSource','groundSource'):
    shader = re.search(r'static let '+name+r' = """\n(.*?)\n    """',source,re.S).group(1)
    floats = sorted(set(re.findall(r'\bu_[a-zA-Z]+\b',shader))-{'u_texture','u_field','u_terrainField'})
    header = '#version 100\nprecision mediump float;\nuniform sampler2D u_texture;\nvarying vec2 v_tex_coord;\nvarying vec4 v_color_mix;\n'
    header += ''.join('uniform float '+x+';\n' for x in floats)
    header += 'varying float a_depth;\n' if name=='surfaceSource' else 'varying vec2 a_origin;\nuniform sampler2D u_field;\nuniform sampler2D u_terrainField;\n'
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/(name+'.frag');path.write_text(header+shader)
        subprocess.run([validator,'-S','frag',str(path)],check=True)
    print('PASS GLES 1.00 fragment syntax:',name)
print('This check does not replace SpriteKit runtime shader translation or visual acceptance.')
