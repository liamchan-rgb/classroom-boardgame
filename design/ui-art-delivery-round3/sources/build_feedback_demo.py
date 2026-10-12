"""Offline motion specification only. Never invokes App state or rules."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
for aspect in ['16x9','4x3']:
 svg=(ROOT/'sources'/f'public_battle_b_{aspect}_feedback.svg').read_text()
 doc='''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>一次文字反馈 · 离线设计演示</title>
<style>body{margin:0;background:#eff7fb}svg{display:block;width:100%;height:auto}#committed-feedback{opacity:0;pointer-events:none}.play-once{animation:delta 1300ms ease 1 both}@keyframes delta{0%{opacity:0}11.538%{opacity:1}80.769%{opacity:1}100%{opacity:0}}@media(prefers-reduced-motion:reduce){.play-once{animation:deltaReduced 1300ms steps(1,end) 1 both}@keyframes deltaReduced{0%,80.769%{opacity:1}100%{opacity:0}}}</style>'''+svg+'''
<script>
// Review fixture: event identity is persisted for this document's lifetime.
// Re-rendering, view switching, resize and repeated delivery do not restart it.
// Reload/restore behavior is an App integration requirement, not proven by HTML.
const consumed=new Set();let played=0;
function showCommittedDelta(eventID){
 if(consumed.has(eventID))return false;
 consumed.add(eventID);played++;
 const node=document.querySelector('#committed-feedback');node.classList.add('play-once');
 return true;
}
window.reviewMotion={showCommittedDelta,get played(){return played},durationMs:1300};
showCommittedDelta('demo_committed_heavy_strike_001');
</script></html>'''
 (ROOT/'previews'/f'public_feedback_once_{aspect}.html').write_text(doc)
print('Built two offline one-time feedback review documents')
