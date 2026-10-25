// Static preview of saved Control rectangles and theme values. No game window,
// screenshot, input automation, or inference. This does not emulate GPU shaders.
const fs = require('fs');
const path = require('path');
const dependencyRoot = process.env.CODEX_NODE_MODULES || 'C:/Users/Admin/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules';
const sharp = require(path.join(dependencyRoot, 'sharp'));
const root = path.resolve(__dirname, '..');
const dir = path.join(root, 'evidence', 'ui_redesign');
const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'layout_manifest.json'), 'utf8'));
const esc = s => String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const uri = resource => {
 const file = path.join(root, 'game', resource.replace('res://',''));
 return `data:image/${file.endsWith('.svg') ? 'svg+xml' : 'png'};base64,${fs.readFileSync(file).toString('base64')}`;
};
const byName = new Map(manifest.items.filter(i=>i.name).map(i=>[i.name,i]));
function zIndex(item) {
 let z = item.z;
 let current = item.name;
 while(current && current.includes('/')) {
  current = current.slice(0,current.lastIndexOf('/'));
  z += byName.get(current)?.z || 0;
 }
 return z;
}
function wrap(text, width, size) {
 const result = [];
 for(const paragraph of String(text).split('\n')) {
  let line='', pixels=0;
  for(const c of paragraph) {
   const step = c.charCodeAt(0)>255 ? size : size*0.56;
   if(pixels + step > width && line) {result.push(line);line='';pixels=0;}
   line+=c; pixels+=step;
  }
  result.push(line);
 }
 return result;
}
const output = [];
let counter=0;
for(const i of [...manifest.items].sort((a,b)=>zIndex(a)-zIndex(b))) {
 const {x,y,width:w,height:h} = i;
 if(i.background) output.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${i.background}" stroke="${i.border||'none'}" stroke-width="${i.border_width||0}"/>`);
 if(i.progress != null) output.push(`<rect x="${x}" y="${y}" width="${w*i.progress}" height="${h}" fill="#74c6b6"/>`);
 if(i.image) {
  if(i.stretch_mode === 1) {
   output.push(`<defs><pattern id="grid${counter}" width="32" height="32" patternUnits="userSpaceOnUse"><image href="${uri(i.image)}" width="32" height="32"/></pattern></defs><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="url(#grid${counter})" opacity="0.2"/>`);
  } else {
   if(i.tint) output.push(`<defs><filter id="tint${counter}" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="${i.tint[0]} 0 0 0 0 0 ${i.tint[1]} 0 0 0 0 0 ${i.tint[2]} 0 0 0 0 0 1 0"/></filter></defs>`);
   output.push(`<image x="${x}" y="${y}" width="${w}" height="${h}" href="${uri(i.image)}" ${i.tint ? `filter="url(#tint${counter})"` : ''} style="image-rendering:pixelated"/>`);
  }
 }
 if(i.name?.endsWith('/Frame')) {
  output.push('<path d="M64 128V114H86 M1194 114H1216V128 M64 546V560H86 M1194 560H1216V546" stroke="#74c6b6" stroke-width="2" fill="none"/><path d="M28 69H1252" stroke="#36504f"/>');
 }
 if(i.text) {
  const padding = i.type === 'TextEdit' ? 14 : i.type === 'Button' || i.type === 'OptionButton' ? 12 : 0;
  const size = i.font_size;
  const lines = i.wrap ? wrap(i.text,w-padding*2,size) : String(i.text).split('\n');
  const maxLines = Math.max(1,Math.floor(h/(size*1.35)));
  const selected = lines.slice(0,maxLines);
  let textX = x+padding;
  const anchor = i.align===2 ? 'end' : i.align===1 ? 'middle' : 'start';
  if(i.align===2) textX=x+w-padding;
  if(i.align===1) textX=x+w/2;
  let textY = y + size*1.05;
  if(i.type==='Button' || i.type==='OptionButton' || i.type==='TextEdit') textY=y+(h-size*1.35)/2+size*1.05;
  output.push(`<defs><clipPath id="text${counter}"><rect x="${x}" y="${y}" width="${w}" height="${h}"/></clipPath></defs><text x="${textX}" y="${textY}" font-size="${size}" fill="${i.color}" text-anchor="${anchor}" xml:space="preserve" clip-path="url(#text${counter})">${selected.map((s,index)=>`<tspan x="${textX}" dy="${index ? size*1.35 : 0}">${esc(s)}</tspan>`).join('')}</text>`);
 }
 counter++;
}
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="836" viewBox="0 0 1280 836"><rect width="1280" height="836" fill="#060a0d"/><g font-family="Malgun Gothic,맑은 고딕,sans-serif">${output.join('\n')}<text x="40" y="824" font-size="12" fill="#8a9c9d">정적 UI 배치 미리보기 · 저장된 씬의 위치·테마 기반 · 실제 게임 렌더링 캡처 아님</text></g></svg>`;
fs.writeFileSync(path.join(dir,'ui_layout_preview.svg'),svg);
sharp(Buffer.from(svg)).png().toFile(path.join(dir,'ui_layout_preview.png')).then(()=>console.log('STATIC_UI_PREVIEW_WRITTEN'));
