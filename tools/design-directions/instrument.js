(()=>{'use strict';
const catalog=window.JOURNAL_CATALOG, get=k=>catalog.find(t=>t.key===k), esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const keys={anime:['anime-1','anime-0','anime-2','anime-3','anime-22','anime-12'],manga:['manga-0','manga-1','manga-2','manga-3','manga-13','manga-14']},fresh={anime:['anime-15','anime-16'],manga:['manga-16','manga-23']};
// Illustration-only grouping, not verified catalogue season counts or production mappings.
// Omitted titles intentionally have no invented section hierarchy.
const seriesSections={
 'anime-0':{kind:'season',count:4,current:2},'anime-1':{kind:'season',count:4,current:1},
 'anime-2':{kind:'season',count:2,current:2},'anime-22':{kind:'season',count:3,current:2}
};
function sectionName(k){const section=seriesSections[k];return section?`${section.kind==='season'?'Season':'Part'} ${section.current}`:''}
function sectionWindow(section){
 if(section.count<=4)return Array.from({length:section.count},(_,i)=>i+1);
 const start=Math.max(1,Math.min(section.current-1,section.count-2)),end=start+2;
 return [...(start>1?['…']:[]),start,start+1,end,...(end<section.count?['…']:[])];
}
// One index grammar for large and compact Anime cards. Browsing never changes tracking.
function seasonNumbers(k){
 const section=seriesSections[k];if(!section)return '';
 return `<span class="season-line" aria-hidden="true">${sectionWindow(section).map(n=>`<span class="line-season${n===section.current?' is-current':''}${n==='…'?' is-gap':''}">${n}</span>`).join('')}</span>`;
}
function sceneSeasons(k){
 const section=seriesSections[k];if(!section)return '';
 return `<button class="scene-seasons" data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${section.count}. View seasons">${seasonNumbers(k)}</button>`;
}
function seasonStrip(k,compact=false){
 const section=seriesSections[k];if(!section||section.count<2)return '';
 const plural=section.kind==='season'?'seasons':'parts';
 return `<button class="season-strip${compact?' compact-seasons':''}" data-kind="${section.kind}" data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${section.count}. View ${plural}"><span class="season-prefix">${section.kind==='part'?'Parts':'Seasons'}</span><span class="season-rail" aria-hidden="true"><span class="season-numbers">${sectionWindow(section).map(n=>`<span class="season-number${n===section.current?' is-current':''}${n==='…'?' season-gap':''}"><span>${n}</span></span>`).join('')}</span><span class="season-arrow"><svg viewBox="0 0 16 16"><path d="m6 4 4 4-4 4"/></svg></span></span></button>`;
}
function currentSectionProgress(k){return `${get(k).medium==='anime'?'Episode':'Chapter'} ${state[k].n}${capped(k)?' · Caught up':''}`}
function seriesOverview(k,tracked=true){
 const section=seriesSections[k];if(!section)return '';viewedSection=section.current;
 const label=section.kind==='season'?'Season':'Part';
 return `<section class="series-overview" aria-label="${label==='Season'?'Seasons':'Parts'} of ${esc(get(k).title)}"><div class="series-overview-heading"><h3 tabindex="-1">${label==='Season'?'Seasons':'Parts'}</h3><small>${section.count} ${label==='Season'?'seasons':'parts'}</small></div><div class="section-panels" role="group" aria-label="Browse ${label.toLowerCase()}s">${Array.from({length:section.count},(_,i)=>`<button class="section-panel${i+1===section.current?' is-resume':''}" data-section="${i+1}" aria-pressed="${i+1===section.current}" aria-label="View ${label.toLowerCase()} ${i+1}${i+1===section.current?', current '+(get(k).medium==='anime'?'season':'part'):''}"><span class="panel-index" aria-hidden="true">${i+1}</span><span class="panel-foot" aria-hidden="true">${i+1===section.current?'Current':'<span class="panel-rule"></span>'}</span></button>`).join('')}</div><div class="selection-thread" aria-hidden="true"></div><div class="section-status" role="status" aria-live="polite"><span data-section-name>${label} ${section.current}</span><span data-section-state>${tracked?currentSectionProgress(k):'Not in your list'}</span></div><div class="section-unknown" hidden><p>Progress unknown.</p><button data-return-current>Back to ${label.toLowerCase()} ${section.current}<span aria-hidden="true">↗</span></button></div></section>`;
}
function previewSection(n){
 const section=seriesSections[selected];if(!section||n<1||n>section.count)return;
 viewedSection=n;const current=n===section.current,label=section.kind==='season'?'Season':'Part';dialog.style.setProperty('--selection-center',((n-.5)/section.count*100)+'%');
 dialog.querySelectorAll('[data-section]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.section)===n)));
 dialog.querySelector('[data-section-name]').textContent=label+' '+n;
 dialog.querySelector('[data-section-state]').textContent=current?(scenario!=='new'&&state[selected]?currentSectionProgress(selected):'Not in your list'):'Preview';
 dialog.querySelector('.section-unknown').hidden=current;const progress=dialog.querySelector('.detail-progress');if(progress)progress.hidden=!current;renderSectionContent(selected,n);
 animate(dialog.querySelector('.edition-slot'),[{opacity:.5,transform:'translateY(4px)'},{opacity:1,transform:'translateY(0)'}],{duration:200,easing:'cubic-bezier(.2,.8,.25,1)'});
}
// Illustrative club readers and newly released chapter ranges, separate from unread backlog.
const mangaActivity={
 'manga-0':{readers:['Mina'],newChapters:1},'manga-1':{readers:['Mina','Jules'],newChapters:1},
 'manga-2':{readers:['Jules'],newChapters:2},'manga-3':{readers:[],newChapters:0},
 'manga-13':{readers:['Ari'],newChapters:0},'manga-14':{readers:[],newChapters:0}
};
function newChapterCount(k){const current=state[k],activity=mangaActivity[k];return current?.max!=null&&activity?Math.max(0,Math.min(activity.newChapters,current.max-current.n)):0}
function chapterLabel(k,compact=false){const n=newChapterCount(k);return n?`${n} new${compact?'':' chapter'+(n===1?'':'s')}`:state[k]?.max!=null&&capped(k)?'Up to date':''}
function mangaReaders(k){const names=mangaActivity[k]?.readers||[];if(!names.length)return '';return `<button class="club-link manga-readers" data-club="${k}" data-club-context="readers" aria-label="See ${esc(names.join(' and '))} reading ${esc(get(k).title)} in Sunday Club"><span class="club-initial" aria-hidden="true">${names[0][0]}</span><span>${esc(names.join(' + '))}</span><span aria-hidden="true">›</span></button>`}
function mangaContext(k,compact=false){const label=chapterLabel(k,compact),readers=mangaReaders(k);if(compact&&!label&&!readers)return '';return `<div class="manga-context${compact?' compact-context':''}"><span class="chapter-update" data-chapter-update="${k}" data-compact="${compact}" ${label?'':'hidden'}><span class="chapter-mark" aria-hidden="true"><svg viewBox="0 0 12 14"><path d="M2 1h6l2 2v10H2zM4 5h4M4 8h4"/></svg></span><span>${label}</span></span>${readers}</div>`}
const seasonStudy=new URLSearchParams(location.search).get('seasons')==='compare';
const feed=document.querySelector('#feed'),phone=document.querySelector('.phone'),dialog=document.querySelector('#detail'),selector=document.querySelector('.selector');
let scrollFrame=0;
const homeMotions=new Set();
const switchStudies=['margin','exposure','relay','interlock','signature'];
const switchFamilies=['noir','poster','glass','edgewise','keys'];
const switchDirections=[...switchFamilies,'objects',...switchStudies,'compact','shelf','masthead','diptych','edge','ribbon','dial','window'];
const requestedSwitch=new URLSearchParams(location.search).get('switch');
if(new URLSearchParams(location.search).get('embed')==='1')document.body.dataset.embed='true';
phone.dataset.switch=switchDirections.includes(requestedSwitch)?requestedSwitch:'poster';
// Opt-in Manga Home studies; the default composition stays unchanged.
const requestedReading=new URLSearchParams(location.search).get('reading');
if(phone.dataset.switch==='poster'&&[...(window.KURO_MANGA_DIRECTIONS?.names||[]),...(window.KURO_MANGA_PHILOSOPHIES?.names||[])].includes(requestedReading))phone.dataset.reading=requestedReading;
if(phone.dataset.switch==='poster'&&!phone.dataset.reading)phone.dataset.reading='library';
const requestedMedium=new URLSearchParams(location.search).get('medium');
let homePage='home';
let medium='anime',scenario='busy',state={},saved=new Set(),undo=null,selected=null,origin=null,originLocator=null,spoilers=new Set(),detailClub=false,viewedSection=null,openDays=new Set(['date-0']),expandedDays=new Set(),calendarLimit=4,suppressClickUntil=0,lastAction=null;
try{medium=localStorage.getItem('kuro-instrument-medium')==='manga'?'manga':'anime'}catch{}
if(seasonStudy)medium='anime';else if(['anime','manga'].includes(requestedMedium))medium=requestedMedium;
// Each study uses its own visual object; semantic medium buttons remain immediately usable.
const mediumWord=(m)=>`<span class="mode-name">${m==='anime'?'Anime':'Manga'}</span><span class="mode-meta" hidden></span>`;
if(switchFamilies.includes(phone.dataset.switch)){
 selector.dataset.family=phone.dataset.switch;
 selector.innerHTML=`<div class="family-control">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}"><span class="family-type" style="--letter-art:url('${esc(get(keys[m][0]).cover)}')">${mediumWord(m)}</span><span class="family-mark" aria-hidden="true"></span></button>`).join('')}</div>`;
 if(['noir','edgewise'].includes(phone.dataset.switch))document.querySelector('.device').append(selector);
}else if(phone.dataset.switch==='objects'){
 selector.innerHTML=`<div class="medium-objects">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}"><span class="material-object" aria-hidden="true"><span class="material-sprite"></span></span><span class="material-caption">${mediumWord(m)}<span class="material-index" aria-hidden="true"></span></span></button>`).join('')}</div>`;
 const materialProbe=new Image();materialProbe.onload=()=>{selector.dataset.material='ready'};materialProbe.onerror=()=>{selector.dataset.material='unavailable'};materialProbe.src='assets/medium-objects-v47.png';
}else if(switchStudies.includes(phone.dataset.switch)){
 selector.classList.add('study-selector');
 selector.innerHTML=`<div class="medium-study medium-${phone.dataset.switch}">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}">${['exposure','relay'].includes(phone.dataset.switch)?`<span class="study-art" aria-hidden="true"><img src="${esc(get(keys[m][0]).cover)}" alt=""></span>`:''}<span class="study-word">${mediumWord(m)}</span><span class="study-corner" aria-hidden="true"></span><span class="study-arrow" aria-hidden="true">↗</span></button>`).join('')}<span class="study-divider" aria-hidden="true"></span></div>`;
}else if(phone.dataset.switch==='compact'){
 selector.innerHTML=`<div class="compact-medium"><span class="compact-surface" aria-hidden="true"></span>${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}"><span class="compact-symbol" aria-hidden="true">${m==='anime'?'<svg viewBox="0 0 20 20"><rect x="2.5" y="5" width="15" height="10" rx="2"/><path d="M6 2.5h8M6 17.5h8"/></svg>':'<svg viewBox="0 0 20 20"><path d="M3 3.5h10l4 3v10H3zM13 3.5v3h4M6 8h6M6 11h8M6 14h5"/></svg>'}</span>${mediumWord(m)}</button>`).join('')}</div>`;
 document.querySelector('.app-header').insertBefore(selector,document.querySelector('.page-location'));
}else if(phone.dataset.switch==='shelf'){
 selector.innerHTML=`<div class="medium-shelves">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}"><span class="switch-stack" aria-hidden="true">${keys[m].slice(0,3).map((k,i)=>`<img src="${esc(get(k).cover)}" alt="" style="--leaf:${i}">`).join('')}</span><span class="switch-heading">${mediumWord(m)}<span class="shelf-arrow" aria-hidden="true">↗</span></span></button>`).join('')}</div>`;
}else if(phone.dataset.switch==='masthead'){
 selector.innerHTML=`<div class="medium-masthead">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}">${mediumWord(m)}<span class="masthead-thumb" aria-hidden="true"><img src="${esc(get(keys[m][0]).cover)}" alt=""><i>↗</i></span></button>`).join('')}<span class="masthead-rule" aria-hidden="true"></span></div>`;
}else if(phone.dataset.switch==='diptych'){
 selector.innerHTML=`<div class="editorial-medium"><img class="medium-panorama" src="assets/medium-diptych-v43.jpg" alt="" aria-hidden="true"><div class="medium-doors"><button data-medium="anime" aria-label="Anime"><span class="medium-paper">${mediumWord('anime')}<span class="medium-turn" aria-hidden="true">↗</span></span></button><button data-medium="manga" aria-label="Manga"><span class="medium-paper">${mediumWord('manga')}<span class="medium-turn" aria-hidden="true">↗</span></span></button></div><span class="medium-ink" aria-hidden="true"></span></div>`;
}else if(phone.dataset.switch==='edge'){
 const glyph=(m)=>m==='anime'?'<svg viewBox="0 0 40 32"><rect x="2" y="4" width="36" height="24" rx="3"/><path d="M9 4v24M31 4v24M2 10h7M2 22h7M31 10h7M31 22h7M17 11l9 5-9 5z"/></svg>':'<svg viewBox="0 0 40 32"><path d="M20 7C14 3 8 3 3 5v22c6-2 12-1 17 2 5-3 11-4 17-2V5c-5-2-11-2-17 2zM20 7v22M8 10l7 1M8 15l7 1M25 11l7-1M25 16l7-1"/></svg>';
 selector.innerHTML=`<div class="edge-options">${['anime','manga'].map(m=>`<button data-medium="${m}" aria-label="${m==='anime'?'Anime':'Manga'}"><span class="edge-symbol" aria-hidden="true">${glyph(m)}</span>${mediumWord(m)}<span class="edge-arrow" aria-hidden="true">↗</span></button>`).join('')}</div>`;
}else if(phone.dataset.switch==='ribbon'){
 selector.innerHTML=`<div class="medium-ribbon" aria-hidden="true"><div class="ribbon-film"><img src="${get('anime-1').banner}" alt=""><i></i><i></i></div><div class="ribbon-paper"><img src="${get('manga-0').cover}" alt=""><span></span></div></div><div class="mode-options"><button data-medium="anime" aria-label="Anime">${mediumWord('anime')}</button><button data-medium="manga" aria-label="Manga">${mediumWord('manga')}</button></div>`;
}else if(phone.dataset.switch==='dial'){
 selector.innerHTML=`<div class="mode-options"><button data-medium="anime" aria-label="Anime">${mediumWord('anime')}</button><button class="world-dial" data-flip-medium aria-label="Turn the media dial"><span class="dial-ring" aria-hidden="true"><i></i><b></b></span><span class="dial-hub" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M8 5l9 7-9 7zM5 5v14"/></svg></span></button><button data-medium="manga" aria-label="Manga">${mediumWord('manga')}</button></div>`;
}else{
 selector.innerHTML=`<div class="world-windows"><button data-medium="anime" aria-label="Anime"><span class="window-art" aria-hidden="true"><img src="${get('anime-1').banner}" alt=""></span>${mediumWord('anime')}<span class="window-grip" aria-hidden="true"></span></button><button data-medium="manga" aria-label="Manga"><span class="window-art" aria-hidden="true"><img src="${get('manga-0').cover}" alt=""></span>${mediumWord('manga')}<span class="window-grip" aria-hidden="true"></span></button></div>`;
}

const mediumPanorama=selector.querySelector('.medium-panorama');
if(mediumPanorama)mediumPanorama.addEventListener('error',()=>{selector.dataset.artwork='unavailable';});
function reset(){guideChoices.clear();localNotes.clear();state={};for(const m of ['anime','manga'])keys[m].forEach((k,i)=>state[k]={n:m==='anime'?[4,7,6,11,3,8][i]:[24,8,16,12,5,40][i],max:m==='anime'?[5,8,9,37,12,64][i]:[25,9,21,null,null,null][i]});saved.clear();spoilers.clear();undo=null;lastAction=null;openDays=new Set(['date-0']);expandedDays.clear();calendarLimit=4;document.querySelector('#fail').checked=false;document.querySelector('#toast').hidden=true;render()}
function capped(k){return state[k].max!==null&&state[k].n>=state[k].max}
function art(k){return `<img src="${esc(visualFor(k).cover)}" alt="${esc(get(k).title)}" draggable="false">`}
function actionIcon(done=false){return `<svg viewBox="0 0 20 20" aria-hidden="true"><path d="${done?'M4 10l4 4 8-8':'M10 4v12M4 10h12'}"/></svg>`}
function progressDescription(k){const t=get(k),unit=t.medium==='anime'?'episodes watched':'chapters read';return `${sectionName(k)?sectionName(k)+' · ':''}${state[k].n}${state[k].max===null?'':' of '+state[k].max+' available'} ${unit}`}
function progressAction(k){return `${capped(k)?'Caught up on':'Mark next '+(get(k).medium==='anime'?'episode':'chapter')+' of'} ${get(k).title}${capped(k)?'':' complete'}`}
function availability(k){return capped(k)?'Up to date':get(k).medium==='anime'?'New episode available':'New chapter'}
function step(k,compact=false){
 const done=capped(k),unit=get(k).medium==='anime'?'Ep.':'Ch.',known=state[k].max!==null,pct=known?Math.min(100,state[k].n/state[k].max*100):0;
 const section=compact&&get(k).medium==='anime'?seriesSections[k]:null;
 const label=`<span class="progress-label" aria-hidden="true"><span class="progress-unit">${unit}</span><span class="completion-label">Caught up</span><span class="progress-value"><b data-count="${k}">${state[k].n}</b>${known?`<span class="progress-total"> / ${state[k].max}</span>`:''}</span></span>`;
 const summary=section?`<button class="progress-seasons" data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${section.count}. View seasons">${label}${seasonNumbers(k)}</button>`:label;
 return `<div class="progress-control${section?' has-season-line':''}" data-progress="${k}" data-complete="${done}" role="group" aria-label="${esc(progressDescription(k))}"><span class="progress-track" aria-hidden="true" ${known&&!section?'':'hidden'}><span class="progress-trace" data-trace="${k}" style="width:${pct}%"></span></span>${summary}<button class="step" data-step="${k}" aria-label="${esc(progressAction(k))}" ${done?'disabled':''}><span class="key-cap" aria-hidden="true">${actionIcon(done)}</span><span class="success-cap" aria-hidden="true">${actionIcon(true)}</span></button></div>`;
}
// Selected catalog banners keep their original landscape composition. Covers are never stretched into scenes.
const artwork={'anime-1':{focus:'55% 50%'},'anime-0':{focus:'50% 50%'},'anime-15':{focus:'50% 48%'}};
function visualFor(k,n=seriesSections[k]?.current){
 const t=get(k),edition=window.KURO_DETAIL_FIXTURES?.[k]?.sections?.[n]?.artwork;
 const cover=edition?.cover||t.cover,scene=edition?.banner||edition?.cover||t.banner||cover;
 const source=t.medium==='anime'?scene:cover;
 const palette=window.KURO_ART_MATERIALS?.[source]||{base:'#34433e',deep:'#1e2925',wash:'#f0f2ee',edge:'#cbd3cb',ink:'#ffffff'};
 return {cover,scene,source,palette,seasonArtwork:!!edition};
}
function materialStyle(k,n){const v=visualFor(k,n),p=v.palette;return `--scene-tone:${p.base};--art-base:${p.base};--art-deep:${p.deep};--art-wash:${p.wash};--art-edge:${p.edge};--art-ink:${p.ink}`;}
function applyDetailMaterial(k,n){
 const v=visualFor(k,n);dialog.style.cssText=materialStyle(k,n);const count=seriesSections[k]?.count;dialog.style.setProperty('--selection-center',count?((n-.5)/count*100)+'%':'50%');
 dialog.dataset.artwork=v.source;dialog.dataset.artworkScope=v.seasonArtwork?'season':'series-fallback';
 const cover=dialog.querySelector('.detail-object img'),light=dialog.querySelector('.detail-light img');
 if(cover)cover.src=get(k).medium==='anime'?v.scene:v.cover;if(light)light.src=v.scene;dialog.dataset.landscape=String(get(k).medium==='anime'&&v.scene!==v.cover);
}
function sceneArt(k){const v=visualFor(k);return `<img src="${esc(v.scene)}" alt="${esc(get(k).title)}" draggable="false" style="object-position:${artwork[k]?.focus||'50% 50%'}">`;}
function clubShortcut(k){return `<button class="club-link" data-club="${k}" aria-label="See Sunday Club activity for ${esc(get(k).title)}"><span class="club-initial" aria-hidden="true">M</span><span>Mina + Jules</span><span aria-hidden="true">›</span></button>`}
// Titles open details; artwork season markers open the full season overview.
function cardTitle(k){return `<button class="title-open" data-detail="${k}" aria-label="View ${esc(get(k).title)}">${esc(get(k).title)}</button>`}
// Selected design: the current season sits on the cover; progress stays separate.
function compactTitle(k,i,compareNumbers=false){
 const title=medium==='anime'?`<button class="title-open" data-detail="${k}" aria-label="View ${esc(get(k).title)}">${esc(get(k).title)}</button>`:cardTitle(k);
 const marker=medium==='anime'&&seriesSections[k]&&!compareNumbers;
 const target=marker?`data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${seriesSections[k].count}. View seasons"`:`data-detail="${k}" aria-label="Open ${esc(get(k).title)}"`;
 return `<article class="carry-card" style="${materialStyle(k)}" data-active="${k}" data-slot="${i}"><button class="cover" ${target}>${art(k)}${marker?artworkSeasonMarker(k,true):''}</button><h2>${title}</h2>${step(k,compareNumbers&&medium==='anime')}${medium==='manga'?mangaContext(k,true):''}</article>`;
}
function mangaFolio(k,i){
 if(phone.dataset.switch==='poster')return `<article class="folio-title reading-leaf" style="${materialStyle(k)}" data-active="${k}" data-slot="${i}"><div class="folio-art"><button class="cover" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${art(k)}</button><div class="chapter-bookmark">${step(k)}</div></div><h2>${cardTitle(k)}</h2>${mangaContext(k)}</article>`;
 return `<article class="folio-title" style="${materialStyle(k)}" data-active="${k}" data-slot="${i}"><div class="folio-art"><button class="cover" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${art(k)}</button><div class="folio-bookmark">${step(k)}</div></div><h2>${cardTitle(k)}</h2>${mangaContext(k)}</article>`;}
function active(list){
 if(medium==='manga'&&window.KURO_MANGA_PHILOSOPHIES?.names.includes(phone.dataset.reading))return window.KURO_MANGA_PHILOSOPHIES.render(phone.dataset.reading,list,{art,title:cardTitle,progress:step,context:mangaContext,escape:esc,get,position:k=>({...state[k],new:newChapterCount(k),readers:mangaActivity[k]?.readers||[]})});
 if(medium==='manga'&&phone.dataset.reading)return window.KURO_MANGA_DIRECTIONS.render(phone.dataset.reading,list,{art,title:cardTitle,progress:step,context:mangaContext,material:materialStyle,escape:esc,get});
 if(medium==='manga'&&phone.dataset.switch==='poster')return `<div class="reading-spread">${list.slice(0,2).map((k,i)=>mangaFolio(k,i)).join('')}</div><div class="reading-index" aria-label="More current reads">${list.slice(2).map((k,i)=>`<article class="reading-entry" data-active="${k}" data-slot="${i+2}"><button class="cover" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${art(k)}</button><div class="entry-copy"><h2>${cardTitle(k)}</h2>${mangaContext(k,true)}</div><div class="entry-marker">${step(k)}</div></article>`).join('')}</div>`;
 const lead=list.slice(0,2).map((k,i)=>medium==='anime'?`<div class="scene-unit" data-active="${k}" data-slot="${i}"><article class="scene-card" style="${materialStyle(k)}"><div class="study-image"><button class="cover scene-window" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${sceneArt(k)}</button>${artworkSeasonMarker(k)}</div><div class="scene-caption"><div class="scene-title"><h2>${cardTitle(k)}</h2></div>${step(k)}</div><div class="scene-context">${i===1?clubShortcut(k):`<span class="availability" data-availability="${k}">${availability(k)}</span>`}</div></article></div>`:mangaFolio(k,i)).join('');
 return `<div class="${medium==='anime'?'scene-stack':'reading-folio'}">${lead}</div><div class="rotation-heading"><h2>${medium==='anime'?'Also watching':'On your shelf'}</h2><span>4 titles</span></div><div class="carry-grid">${list.slice(2).map((k,i)=>compactTitle(k,i+2)).join('')}</div>`;
}
function suggestionVibe(k){const copy={'anime-16':'A quiet kind of courage.','manga-16':'Rage gives way to purpose.','manga-23':'Odd company. Electric chemistry.'};return copy[k]||get(k).vibe;}
// Concise premises paraphrased from GKIDS, Kodansha and VIZ; sources in README.
function storyCopy(k){const copy={
 'anime-15':{kind:'FILM · ROMANCE',premise:'Two strangers wake up in each other’s lives.'},
 'anime-16':{kind:'FILM · DRAMA',premise:'A former bully seeks forgiveness from the deaf girl he hurt.'},
 'manga-16':{kind:'MANGA · HISTORICAL',premise:'A young Viking dreams of a land beyond war.'},
 'manga-23':{kind:'MANGA · SUPERNATURAL',premise:'Two teens test their beliefs in ghosts and aliens.'}
};return copy[k]||{kind:medium==='anime'?'ANIME':'MANGA',premise:suggestionVibe(k)}}
function newTitles(){return `<section class="suggestions" aria-label="${scenario==='new'?'Start your list':'Recommendations'}"><div class="section-head"><h2>${scenario==='new'?'A first favourite.':medium==='anime'?'Your next story.':'Turn to something new.'}</h2></div><div class="story-list">${fresh[medium].map((k,i)=>{const copy=storyCopy(k),landscape=medium==='anime'&&get(k).banner;return `<article class="story-card ${landscape?'story-landscape':''}" data-story="${k}"><button class="story-open" data-detail="${k}" aria-label="Explore ${esc(get(k).title)}"><span class="story-art">${landscape?sceneArt(k):art(k)}</span><span class="story-copy"><span class="story-kind">${copy.kind}</span><span class="story-title" role="heading" aria-level="3">${esc(get(k).title)}</span><span class="story-premise">${esc(copy.premise)}</span></span></button><div class="story-save">${saveButton(k)}</div></article>`}).join('')}</div></section>`}

function saveButton(k){return `<button class="save" data-save="${k}" aria-label="${saved.has(k)?'Remove '+esc(get(k).title)+' from your list':'Plan to '+(get(k).medium==='anime'?'watch ':'read ')+esc(get(k).title)}" aria-pressed="${saved.has(k)}"><span>${saved.has(k)?'Planned':get(k).medium==='anime'?'Plan to watch':'Plan to read'}</span><span class="save-mark" aria-hidden="true"><svg viewBox="0 0 20 24"><path d="M4 3h12v18l-6-4-6 4z"/>${saved.has(k)?'<path class="bookmark-tick" d="M7 9l2 2 4-4"/>':''}</svg></span></button>`}
// A local density fixture, not a real release calendar. All events retain a followed-title key.
function releaseGroups(){
 if(scenario==='undated')return [];
 const full=scenario==='full',offsets=full?[0,1,4,7,14,21,28,35]:[0,1,7];
 return offsets.map((offset,g)=>{
  const date=new Date(Date.UTC(2026,9,2+offset)),day=date.toLocaleDateString('en-GB',{day:'numeric',timeZone:'UTC'}),month=date.toLocaleDateString('en-GB',{month:'short',timeZone:'UTC'}),label=offset===0?'Today':offset===1?'Tomorrow':date.toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short',timeZone:'UTC'});
  const titles=full?keys[medium]:g===0?keys[medium].slice(0,3):g===1?keys[medium].slice(3,5):keys[medium].slice(5);
  return {id:'date-'+g,day,month,label,events:titles.map((k,i)=>({id:`${medium}-${g}-${i}`,key:k,unit:medium==='anime'?(seriesSections[k]?'S'+seriesSections[k].current+' · ':'')+'Episode '+([5,8,9,37,12,64][keys.anime.indexOf(k)]+g+1):i%3===1?'Volume '+(10+g+i):'Chapter '+([25,9,21,12,5,40][keys.manga.indexOf(k)]+g+1),time:medium==='anime'?(i===4?'Time TBA':`${16+i}:00`):i%3===1?'English edition':'Chapter release'}))};
 });
}
function eventRow(event){return `<button class="release-row" data-event-id="${event.id||'pending-'+event.key}" data-detail="${event.key}" aria-label="Open ${esc(get(event.key).title)}, ${event.unit}, ${event.time}">${art(event.key)}<span class="release-copy"><strong>${esc(get(event.key).title)}</strong><small>${event.unit}</small></span><span class="release-when">${event.time}</span><span class="row-arrow" aria-hidden="true">›</span></button>`}
function dayBody(group){const expanded=expandedDays.has(group.id),shown=expanded?group.events:group.events.slice(0,3),remaining=group.events.length-3;return `${shown.map(eventRow).join('')}${remaining>0?`<button class="release-more" data-more-day="${group.id}" aria-expanded="${expanded}"><span>${expanded?'Show fewer':`Show ${remaining} more releases`}</span><span class="disclosure-mark" aria-hidden="true">⌄</span></button>`:''}`}
function dayGroup(group){const open=openDays.has(group.id);return `<div class="release-day" data-release-day="${group.id}"><button class="day-toggle" data-day="${group.id}" aria-expanded="${open}" aria-controls="body-${group.id}" aria-label="${group.label}, ${group.events.length} release${group.events.length===1?'':'s'}"><span class="date-stamp" aria-hidden="true"><b>${group.day}</b><small>${group.month}</small></span><span class="day-copy"><strong>${group.label}</strong><small>${group.events.length} release${group.events.length===1?'':'s'}</small></span><span class="day-art" aria-hidden="true">${group.events.slice(0,3).map(e=>art(e.key)).join('')}</span><span class="disclosure-mark" aria-hidden="true">⌄</span></button><div class="day-events" id="body-${group.id}" ${open?'':'hidden'}>${dayBody(group)}</div></div>`}
function pendingGroup(){const pending=keys[medium].slice(3),open=openDays.has('pending');return `<div class="release-day pending-day"><button class="day-toggle" data-day="pending" aria-expanded="${open}" aria-controls="body-pending" aria-label="Dates pending, ${pending.length} announcements"><span class="date-stamp pending-stamp" aria-hidden="true">…</span><span class="day-copy"><strong>Dates to come</strong><small>${pending.length} announcements</small></span><span class="day-art" aria-hidden="true">${pending.slice(0,3).map(art).join('')}</span><span class="disclosure-mark" aria-hidden="true">⌄</span></button><div class="day-events" id="body-pending" ${open?'':'hidden'}>${pending.map(k=>eventRow({key:k,unit:medium==='anime'?'New season':'New edition',time:'Date TBA'})).join('')}</div></div>`}
function calendarBody(){const groups=releaseGroups(),visible=groups.slice(0,calendarLimit),remaining=groups.length-visible.length;return `<div class="dated-groups">${visible.map(dayGroup).join('')}</div>${groups.length?'':'<p class="calendar-empty">No confirmed dates yet.</p>'}${remaining?`<button class="calendar-more" data-more-calendar>Next ${Math.min(4,remaining)} dates <span>${groups.slice(calendarLimit,calendarLimit+4).reduce((n,g)=>n+g.events.length,0)} releases <span aria-hidden="true">↓</span></span></button>`:''}${pendingGroup()}`}
// A visible summary of the same calendar, rather than a second release data source.
function upcomingGlance(){
 const groups=releaseGroups(),next=groups[0],total=groups.reduce((n,g)=>n+g.events.length,0),pending=keys[medium].slice(3);
 const titles=next?next.events.map(event=>event.key):pending;
 const caption=next?`${next.label} · ${next.events.length} releases`:'Dates still to come';
 return `<button class="upcoming-glance" data-upcoming aria-controls="upcoming-calendar" aria-label="Coming up: ${caption}, ${total?total+' dated releases':pending.length+' announcements'}. Open full calendar"><span class="upcoming-copy"><b>Coming up</b><small>${caption}</small></span><span class="upcoming-art" aria-hidden="true">${titles.slice(0,3).map(art).join('')}</span><span class="upcoming-total" aria-hidden="true"><b>${total||pending.length}</b><small>${total?(scenario==='full'?'6 weeks':'this week'):'pending'}</small></span><span class="upcoming-arrow" aria-hidden="true">↓</span></button>`;
}
function goToUpcoming(){
 const calendar=feed.querySelector('#upcoming-calendar');
 if(!calendar)return;
 // Scroll only the phone surface; focus follows without triggering another jump.
 const top=calendar.getBoundingClientRect().top-phone.getBoundingClientRect().top+phone.scrollTop-phone.querySelector('.app-header').offsetHeight-12;
 phone.scrollTo({top:Math.max(0,top),behavior:reduced()?'instant':'smooth'});
 calendar.focus({preventScroll:true});
}
function schedule(){const groups=releaseGroups(),total=groups.reduce((n,g)=>n+g.events.length,0);return `<section class="coming-up" id="upcoming-calendar" tabindex="-1" aria-label="Upcoming from your list"><div class="section-head"><h2>Coming up.</h2><small>${total?total+' releases · '+(scenario==='full'?'6 weeks':'7 days'):'From your list'}</small></div><div class="release-calendar">${calendarBody()}</div></section>`}
function toggleDay(id){const opened=!openDays.has(id);opened?openDays.add(id):openDays.delete(id);feed.querySelector(`[data-day="${id}"]`).setAttribute('aria-expanded',String(opened));feed.querySelector('#body-'+id).hidden=!opened;}
function moreDay(id){expandedDays.has(id)?expandedDays.delete(id):expandedDays.add(id);const group=releaseGroups().find(g=>g.id===id),body=feed.querySelector('#body-'+id);body.innerHTML=dayBody(group);body.querySelector('[data-more-day]')?.focus({preventScroll:true});}
function moreCalendar(){const groups=releaseGroups(),next=groups.slice(calendarLimit,calendarLimit+4),button=feed.querySelector('[data-more-calendar]');feed.querySelector('.dated-groups').insertAdjacentHTML('beforeend',next.map(dayGroup).join(''));calendarLimit+=next.length;const remaining=groups.length-calendarLimit;if(remaining)button.innerHTML=`Next ${Math.min(4,remaining)} dates <span>${groups.slice(calendarLimit,calendarLimit+4).reduce((n,g)=>n+g.events.length,0)} releases ↓</span>`;else button.remove();feed.querySelector(`[data-day="${next[0].id}"]`)?.focus({preventScroll:true});}
function clubNote(){const k=keys[medium][3],other=keys[medium][1];return `<section class="club-section club-room" aria-label="Sunday Club activity"><div class="club-masthead"><span class="club-seal" aria-hidden="true"><svg viewBox="0 0 40 40"><path d="M9 9h22v22H9zM14 14h12v12H14zM4 20h10M26 20h10M20 4v10M20 26v10"/></svg></span><div><span class="club-kicker">YOUR PRIVATE CLUB</span><h2>Sunday Club</h2></div><span class="member-stack" aria-label="Members Mina, Jules and Ari"><span>M</span><span>J</span><span>A</span></span></div><div class="club-note"><div class="club-entry"><button class="club-title-art" data-club="${k}" aria-label="See club activity for ${esc(get(k).title)}">${art(k)}</button><div class="club-copy"><div class="person-line"><b>Mina</b><small>2h ago</small></div><p>“Just one more.<br>Famous last words.”</p><button class="club-title" data-club="${k}">Finished ${esc(get(k).title)} <span aria-hidden="true">›</span></button></div></div><button class="spoiler" data-spoiler aria-expanded="${spoilers.has(medium)}" aria-controls="club-spoiler"><span>${spoilers.has(medium)?'Hide spoiler':'Mina’s thought on the ending'}</span><span class="spoiler-key" aria-hidden="true">⌄</span></button><p id="club-spoiler" class="spoiler-content" ${spoilers.has(medium)?'':'hidden'}>Sample spoiler: that quiet final scene changes the opening.</p></div><button class="club-secondary" data-club="${other}">${art(other)}<span><b>Jules started</b><span>${esc(get(other).title)}</span></span><span class="row-arrow" aria-hidden="true">›</span></button><div class="club-room-footer"><span>Shared stories. Your people.</span><span>2 updates</span></div></section>`}
function updateOpening(){phone.dataset.medium=medium;phone.style.setProperty('--reading-one',visualFor(keys.manga[0]).palette.base);phone.style.setProperty('--reading-two',visualFor(keys.manga[1]).palette.base);const available=scenario==='new'?0:medium==='manga'?keys.manga.reduce((total,k)=>total+newChapterCount(k),0):keys.anime.slice(0,2).filter(k=>!capped(k)).length;document.querySelector('.opening-eyebrow').textContent=scenario==='new'?'YOUR COLLECTION':medium==='anime'?'NOW WATCHING':'NOW READING';document.querySelector('.opening-copy h1').textContent=scenario==='new'?'Begin here.':available?available+' new '+(medium==='anime'?'episode':'chapter')+(available===1?'':'s'):medium==='anime'?'Keep watching.':'Keep reading.';selector.dataset.medium=medium;const dial=selector.querySelector('[data-flip-medium]');if(dial)dial.setAttribute('aria-label','Switch to '+(medium==='anime'?'Manga':'Anime'));selector.querySelectorAll('button[data-medium]').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.medium===medium));b.querySelector('.mode-meta').textContent=scenario==='new'?'Start here':b.dataset.medium==='anime'?'6 watching':'6 reading'});}
// Isolated label study: the default Home and its liked detail selector stay intact.
function studyNumbers(k,style,compact=false){
 const section=seriesSections[k];
 const numbers=sectionWindow(section).map(n=>`<span class="study-number${n===section.current?' is-current':''}${n==='…'?' is-gap':''}">${n===section.current&&style==='notch'?`<small>${compact?'S':'Season'}</small>`:''}<b>${n}</b></span>`).join('');
 return `<span class="study-index" aria-hidden="true">${style==='caption'?'<span class="study-caption">Seasons</span>':''}<span class="study-numbers">${numbers}</span></span>`;
}
function studySeasonButton(k,style){
 return `<button class="study-season-control" data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${seriesSections[k].count}. View seasons">${studyNumbers(k,style)}</button>`;
}
function artworkSeasonMarker(k,compact=false){
 if(!seriesSections[k])return '';
 if(compact)return `<span class="study-art-stamp" aria-hidden="true"><small>S</small><b>${seriesSections[k].current}</b></span>`;
 return `<button class="study-art-marker${compact?' is-small':''}" data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${seriesSections[k].count}. View seasons"><span aria-hidden="true"><small>${compact?'S':'Season'}</small><b>${seriesSections[k].current}</b></span></button>`;
}
function studyCompact(k,i,style){
 const card=compactTitle(k,i,style!=='artwork');
 return style==='artwork'?card:card.replace(seasonNumbers(k),studyNumbers(k,style,true));
}
function renderSeasonStudy(){
 document.body.classList.add('season-comparison');phone.dataset.medium='anime';
 const variants=[['notch','Caption notch','The label becomes part of the current-season cut-out.'],['caption','Rail caption','One word is woven into the line; numbers stay quiet.'],['artwork','Artwork tab · selected','Only the current season on the image. All seasons inside.']];
 const k='anime-0';
 feed.innerHTML=`<div class="season-study"><header class="study-heading"><div><a href="instrument.html">KURO / HOME STUDY</a><h1>A name for the numbers.</h1><p>Three directions. Large cards + compact cards.</p></div><button data-study-reset>Reset examples ↺</button></header><div class="study-grid">${variants.map(([style,name,note])=>`<section class="study-option" data-label-style="${style}" aria-label="${name}"><header class="study-option-heading"><h2>${name}</h2><p>${note}</p></header><div class="study-surface"><div class="study-size-label">NOW WATCHING</div><div class="scene-unit" data-active="${k}"><article class="scene-card" style="${materialStyle(k)}"><div class="study-image"><button class="cover scene-window" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${sceneArt(k)}</button>${style==='artwork'?artworkSeasonMarker(k):''}</div><div class="scene-caption"><div class="scene-title"><h2>${cardTitle(k)}</h2></div>${step(k)}</div><div class="scene-context">${clubShortcut(k)}</div>${style==='artwork'?'':studySeasonButton(k,style)}</article></div><div class="rotation-heading"><h2>Also watching</h2></div><div class="carry-grid">${['anime-2','anime-22'].map((key,i)=>studyCompact(key,i,style)).join('')}</div></div></section>`).join('')}</div><footer class="study-footnote">Tap any season treatment to open the existing detail design. Illustrative season counts · browser study only.</footer></div>`;
}

function setHomePage(page){homePage=page;render();phone.scrollTop=0;}
function render(){const glance=document.querySelector('#upcoming-glance-slot');glance.hidden=seasonStudy||homePage!=='home'||scenario==='new';glance.innerHTML=glance.hidden?'':upcomingGlance();if(seasonStudy){renderSeasonStudy();return}updateOpening();feed.dataset.medium=medium;document.querySelector('.page-location').textContent=homePage==='taste'?'Taste':'Home';const pageButton=document.querySelector('[data-home-page]');pageButton.textContent=homePage==='taste'?'Home ›':'‹ Taste';pageButton.setAttribute('aria-label',homePage==='taste'?'Go to Home':'Go to Taste');if(homePage==='taste'){document.querySelector('.opening-eyebrow').textContent='FOR YOUR TASTE';document.querySelector('.opening-copy h1').textContent=medium==='anime'?'Another world.':'Another chapter.';feed.innerHTML=newTitles();observeHome();return}if(scenario==='new'){feed.innerHTML='<section class="empty-home"><span aria-hidden="true">＋</span><h2>Your stories belong here.</h2><p>Import your list to bring your place with you.</p><button data-home-page>Explore Taste <span aria-hidden="true">←</span></button></section>';observeHome();return}feed.innerHTML=`<h1 class="sr-only">${medium==='anime'?'Currently watching':'Currently reading'}</h1>${scenario==='quiet'?'<div class="quiet">Nothing new today. Stay at your own pace.</div>':''}<section class="activity-stage" aria-label="${medium==='anime'?'Currently watching':'Currently reading'}">${active(keys[medium])}<div class="stage-caption" aria-hidden="true"><span></span><span>↓</span></div></section><div class="paper-feed">${schedule()}${clubNote()}</div>`;observeHome()}
const reduced=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;
function animate(el,frames,options){if(!el||reduced())return;const motion=el.animate(frames,options);homeMotions.add(motion);motion.finished.finally(()=>homeMotions.delete(motion)).catch(()=>{});return motion}
// One subtle entrance per section and medium; scrolling or saving never replays it.
const seenSections=new Set();
const entrances=new IntersectionObserver(entries=>{
 for(const entry of entries){if(!entry.isIntersecting)continue;const el=entry.target,key=medium+':'+el.className;entrances.unobserve(el);if(seenSections.has(key))continue;seenSections.add(key);
  const frames=medium==='anime'?[{opacity:.8,transform:'translateY(9px)'},{opacity:1,transform:'translateY(0)'}]:[{opacity:.85,clipPath:'inset(0 0 7% 0)'},{opacity:1,clipPath:'inset(0 0 0 0)'}];
  el.querySelectorAll('.folio-art .cover img,.reading-art .cover img,.reading-study-item .reading-study-cover img,.crosscut-art img,.mp-art img,.library-story img,.story-art img,.release-art img,.club-title-art img').forEach(image=>animate(image,frames,{duration:medium==='anime'?380:260,easing:'cubic-bezier(.2,.75,.25,1)'}));
 }
},{root:phone,threshold:.12});
function observeHome(){entrances.disconnect();feed.querySelectorAll('.reading-folio,.edition-leads,.contact-sheet,.reading-ledger,.crosscut-pair,.mp-root,.coming-up,.club-section,.suggestions').forEach(el=>entrances.observe(el));updateScroll()}
function updateScroll(){const depth=Math.min(1,phone.scrollTop/72);phone.style.setProperty('--scroll-depth',depth);phone.classList.toggle('scrolled',phone.scrollTop>32)}
phone.addEventListener('scroll',()=>{if(scrollFrame)return;scrollFrame=requestAnimationFrame(()=>{updateScroll();scrollFrame=0})},{passive:true});
matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change',()=>{homeMotions.forEach(m=>m.cancel());homeMotions.clear();observeHome()});
window.addEventListener('pagehide',()=>{entrances.disconnect();cancelAnimationFrame(scrollFrame);homeMotions.forEach(m=>m.cancel())});
// One 320ms material transition. Artwork reveals inside fixed, immediately usable targets.
function switchTo(m){
 if(m===medium)return;
 homeMotions.forEach(a=>a.cancel());homeMotions.clear();
 medium=m;openDays=new Set(['date-0']);expandedDays.clear();calendarLimit=4;try{localStorage.setItem('kuro-instrument-medium',m)}catch{}
 document.querySelector('#toast').hidden=true;render();phone.scrollTop=0;updateScroll();
 if(reduced())return;
 if(phone.dataset.switch==='objects'){
  const object=selector.querySelector('[aria-pressed=true] .material-object');
  animate(object,m==='anime'?[{transform:'perspective(400px) rotateY(-12deg) translateY(1px)'},{transform:'perspective(400px) rotateY(0deg) translateY(0)'}]:[{transform:'rotate(-4deg) translateX(-2px)'},{transform:'rotate(0deg) translateX(0)'}],{duration:300,easing:'cubic-bezier(.2,.8,.25,1)'});
 }
 if(phone.dataset.switch==='relay'){
  const identity=selector.querySelector('[aria-pressed=true]');
  animate(identity,[{opacity:.55,transform:'translateX(-3px)'},{opacity:1,transform:'translateX(0)'}],{duration:220,easing:'cubic-bezier(.2,.8,.25,1)'});
 }
 if(['edge','diptych'].includes(phone.dataset.switch)){
  const composition=feed.querySelector(m==='manga'?'.reading-folio':'.scene-stack');
  animate(composition,m==='manga'?[{opacity:.7,transform:'perspective(900px) rotateY(-3deg) translateX(5px)'},{opacity:1,transform:'perspective(900px) rotateY(0deg) translateX(0)'}]:[{opacity:.7,transform:'translateY(6px) scale(.99)'},{opacity:1,transform:'translateY(0) scale(1)'}],{duration:300,easing:'cubic-bezier(.2,.8,.25,1)'});
 }
 feed.querySelectorAll('[data-slot] .cover img').forEach(el=>{
  if(el.getBoundingClientRect().top>phone.getBoundingClientRect().bottom)return;
  animate(el,[{opacity:.65,clipPath:'inset(0 0 5% 0)'},{opacity:1,clipPath:'inset(0 0 0 0)'}],{duration:320,easing:'cubic-bezier(.2,.8,.25,1)'});
 });
 feed.querySelectorAll('.scene-title,.folio-title h2,.reading-caption h2,.carry-card h2').forEach(el=>animate(el,[{opacity:.65},{opacity:1}],{duration:240,easing:'ease-out'}));
}
function toast(message,withUndo=false){const box=dialog.open?dialog.querySelector('.dialog-result'):document.querySelector('#toast');if(!box)return;const restoreFocus=box.contains(document.activeElement);box.hidden=false;box.innerHTML=`<span>${esc(message)}</span><span class="toast-actions">${withUndo?'<button data-undo>Undo</button>':''}<button data-dismiss-toast aria-label="Dismiss notification"><span aria-hidden="true">×</span></button></span>`;if(restoreFocus)box.querySelector(withUndo?'[data-undo]':'[data-dismiss-toast]')?.focus({preventScroll:true})}
function dismissToast(button){button.closest('[role="status"]').hidden=true;if(!lastAction)return;const root=dialog.open?dialog:feed;const target=root.querySelector(`[data-${lastAction.type}="${lastAction.k}"]`);(target&&!target.disabled?target:root.querySelector(`[data-detail="${lastAction.k}"]`))?.focus({preventScroll:true})}
// Patch only the affected state. Covers, scroll, section entrances and neighbouring controls keep their DOM identity.
function syncActions(k){
 window.KURO_MANGA_PHILOSOPHIES?.sync();
 if(dialog.open&&selected===k&&seriesSections[k]&&viewedSection===seriesSections[k].current){const status=dialog.querySelector('[data-section-state]');if(status)status.textContent=currentSectionProgress(k)}
 const t=get(k),done=state[k]?capped(k):false;
 document.querySelectorAll(`[data-progress="${k}"]`).forEach(group=>{
  group.dataset.complete=String(done);group.setAttribute('aria-label',progressDescription(k));
  group.removeAttribute('data-feedback');group.querySelector('[data-count]').textContent=state[k].n;
  const trace=group.querySelector('[data-trace]');if(state[k].max!==null)trace.style.width=Math.min(100,state[k].n/state[k].max*100)+'%';
  const button=group.querySelector('[data-step]'),focused=document.activeElement===button;
  button.disabled=done;button.setAttribute('aria-label',progressAction(k));button.removeAttribute('data-feedback');button.querySelector('.key-cap').innerHTML=actionIcon(done);
  if(done&&focused){const root=dialog.open?dialog:feed;(root.querySelector(`[data-detail="${k}"]`)||root.querySelector('.close'))?.focus({preventScroll:true})}
 });
 document.querySelectorAll(`[data-save="${k}"]`).forEach(button=>{
  const on=saved.has(k);button.setAttribute('aria-pressed',String(on));button.setAttribute('aria-label',on?`Remove ${t.title} from your list`:`Plan to ${t.medium==='anime'?'watch':'read'} ${t.title}`);
  button.firstElementChild.textContent=on?'Planned':t.medium==='anime'?'Plan to watch':'Plan to read';button.removeAttribute('data-feedback');
  const mark=button.querySelector('svg');mark.innerHTML=`<path d="M4 3h12v18l-6-4-6 4z"/>${on?'<path class="bookmark-tick" d="M7 9l2 2 4-4"/>':''}`;
 });
 document.querySelectorAll(`[data-availability="${k}"]`).forEach(el=>el.textContent=availability(k));
 document.querySelectorAll(`[data-chapter-update="${k}"]`).forEach(el=>{const label=chapterLabel(k,el.dataset.compact==='true');el.hidden=!label;el.lastElementChild.textContent=label;});
 if(dialog.open&&selected===k&&dialog.querySelector('.progress-context small'))dialog.querySelector('.progress-context small').textContent=done?'Caught up':state[k].max?state[k].max+' '+(t.medium==='anime'?'episodes':'chapters')+' in this preview':'Ongoing · total unknown';
 if(dialog.open&&selected===k&&state[k]&&(!seriesSections[k]||viewedSection===seriesSections[k].current)){const units=dialog.querySelector('.unit-list');if(units)refreshUnits(k,dialog.querySelector('[data-units]')?.getAttribute('aria-expanded')==='true');}
 updateOpening();
}
function mutate(k,type){
 if(type==='step'&&capped(k))return;lastAction={k,type};
 if(document.querySelector('#fail').checked){document.querySelector('#fail').checked=false;const failed=document.activeElement?.matches(`[data-${type}="${k}"]`)?document.activeElement:(dialog.open?dialog:feed).querySelector(`[data-${type}="${k}"]`);failed?.setAttribute('data-feedback','failed');toast(type==='step'?'Not saved. Your progress is unchanged.':'Not saved. Your list is unchanged.');return}
 undo={k,type,n:state[k]?.n,saved:saved.has(k)};
 if(type==='step')state[k].n++;else saved.has(k)?saved.delete(k):saved.add(k);
 syncActions(k);
 document.querySelectorAll(`[data-${type}="${k}"]`).forEach(el=>{el.dataset.feedback='saved';animate(el.querySelector('.key-cap,.save-mark'),[{transform:'scale(.96)'},{transform:'scale(1)'}],{duration:160,easing:'cubic-bezier(.2,.7,.3,1)'})});
 if(type==='step'){
  document.querySelectorAll(`[data-count="${k}"]`).forEach(el=>{const page=get(k).medium==='manga'&&!el.closest('dialog');animate(el,page?[{opacity:.45,transform:'perspective(180px) rotateX(-48deg) translateY(2px)',transformOrigin:'50% 100%'},{opacity:1,transform:'perspective(180px) rotateX(0deg) translateY(0)',transformOrigin:'50% 100%'}]:[{opacity:.55,transform:'translateY(2px)'},{opacity:1,transform:'translateY(0)'}],{duration:page?280:220,easing:'cubic-bezier(.2,.75,.25,1)'});});
  if(state[k].max)document.querySelectorAll(`[data-trace="${k}"]`).forEach(el=>animate(el,[{width:(undo.n/state[k].max*100)+'%'},{width:(state[k].n/state[k].max*100)+'%'}],{duration:280,easing:'cubic-bezier(.22,.8,.24,1)'}));
 }
 toast(type==='step'?(capped(k)?'Caught up.':'Progress saved.'):(saved.has(k)?'Added to your list.':'Removed from your list.'),true);
}
function toggleSpoiler(){const shown=!spoilers.has(medium);shown?spoilers.add(medium):spoilers.delete(medium);const button=feed.querySelector('[data-spoiler]'),content=feed.querySelector('#club-spoiler');button.setAttribute('aria-expanded',String(shown));button.firstElementChild.textContent=shown?'Hide spoiler':'Mina’s thought on the ending';content.hidden=!shown;if(shown)animate(content,[{opacity:.6},{opacity:1}],{duration:180,easing:'ease-out'})}
// Detail rendering stays local; selecting a season is never a progress mutation.
const detailFixtures=window.KURO_DETAIL_FIXTURES||{};
const guideChoices=new Map();
function adaptationGuide(k){
 const a=detailFixtures[k]?.adaptation;if(!a)return `<section class="adaptation-empty"><span class="detail-eyebrow">On screen</span><p>No verified anime link in this preview.</p></section>`;
 const t=a.key?get(a.key):null,choice=guideChoices.get(k)||'',tracked=a.key&&state[a.key]&&scenario!=='new';
 return `<section class="adaptation-guide" aria-label="Anime and manga connection"><div class="adaptation-heading"><span class="detail-eyebrow">From screen to page</span><h3>Seen the anime?</h3></div><div class="adaptation-title">${t?`<button class="adaptation-cover" data-related="${a.key}" aria-label="Open ${esc(t.title)} anime">${art(a.key)}<span aria-hidden="true">↗</span></button>`:'<span class="adaptation-symbol" aria-hidden="true">映</span>'}<div><b>${esc(t?.title||a.title)}</b><small>Anime adaptation</small>${tracked?`<p class="adaptation-tracking">Your anime list · ${sectionName(a.key)}<br>Episode ${state[a.key].n}</p>`:''}${t?`<button class="source-detail-link" data-related="${a.key}">See anime <span aria-hidden="true">→</span></button>`:`<a class="source-detail-link" href="${esc(a.url)}" target="_blank" rel="noopener noreferrer">Official anime site ↗</a>`}</div></div><details class="watched-guide" ${choice?'open':''}><summary>I've watched the anime<span aria-hidden="true">+</span></summary><label for="finished-season">Which season did you finish?</label><select id="finished-season" data-guide-choice="${k}"><option value="">Choose a season</option>${a.seasons.map(n=>`<option value="${n}" ${String(n)===String(choice)?'selected':''}>Season ${n}</option>`).join('')}</select><div class="guide-result" role="status">${guideResult(k,choice)}</div><small class="guide-footnote">This guide never marks manga chapters as read.</small></details></section>`;
}
function guideResult(k,choice){
 if(!choice)return '<p>Choose a finished season to find your place on the page.</p>';
 const a=detailFixtures[k].adaptation,m=a.coverage?.[choice];
 if(m?.verified&&m.start&&m.end&&m.readNext&&m.evidence){return `<div class="guide-range"><span>Season ${esc(choice)} adapts</span><b>Ch. ${esc(m.start)}–${esc(m.end)}</b></div><div class="guide-recommendation"><small>Continue reading</small><b>Chapter ${esc(m.readNext)}</b></div><a href="${esc(m.evidence)}" target="_blank" rel="noopener noreferrer">Mapping source ↗</a>`;}
 return `<div class="guide-range"><span>After Season ${esc(choice)}</span><b>Chapter match unverified</b></div><p>We haven't verified where this season ends on the page. Your reading position stays unchanged.</p>`;
}
dialog.addEventListener('change',e=>{if(!e.target.matches('[data-guide-choice]'))return;const k=e.target.dataset.guideChoice;guideChoices.set(k,e.target.value);dialog.querySelector('.guide-result').innerHTML=guideResult(k,e.target.value);});
dialog.addEventListener('click',e=>{const b=e.target.closest('[data-related]');if(!b)return;const k=b.dataset.related;if(!get(k))return;selected=k;detailContent(k);dialog.scrollTop=0;dialog.querySelector('.close').focus({preventScroll:true});});
const localNotes=new Map();
function clubRoom(k){
 if(scenario==='new')return '';
 const f=detailFixtures[k]?.circle,own=localNotes.get(k);
 return `<section class="detail-club-room" id="detail-circle" aria-label="People and comments from your clubs">${f?`<header class="circle-art-heading"><div class="circle-cover">${art(k)}</div><div class="circle-art-copy"><span class="detail-eyebrow">Your clubs · private</span><h3>Between us.</h3><span class="tiny-people" aria-hidden="true">${f.people.map(p=>`<i>${esc(p[0][0])}</i>`).join('')}</span><span class="circle-names">${esc(f.people.map(p=>p[0]).join(', '))}</span></div></header><details class="circle-members"><summary>Who's ${get(k).medium==='manga'?'reading':'watching'}<span>${f.people.length} people <i aria-hidden="true">⌄</i></span></summary><div class="circle-roster">${f.people.map(p=>`<div class="circle-person"><span class="circle-avatar" aria-hidden="true">${esc(p[0][0])}</span><span><b>${esc(p[0])}</b><small>${esc(p[1])}</small></span><span class="circle-status">${esc(p[2]).replace(' · ','<br>')}</span></div>`).join('')}</div></details>`:'<h3>Between us.</h3><p class="circle-empty">No activity here yet.</p>'}<div class="circle-comments">${(f?.notes||[]).map(n=>circleNote(n)).join('')}${own?circleNote({name:'You',club:'Local preview',text:own.text,scope:own.scope}):''}</div><details class="circle-compose"><summary><span class="compose-symbol" aria-hidden="true">＋</span><span>${own?'Edit your thought':'Leave a thought'}<small>Shared with your clubs</small></span><span aria-hidden="true">↗</span></summary><form data-note-form><label for="club-note">Your comment</label><textarea id="club-note" name="note" maxlength="500" rows="3" required placeholder="What stayed with you?">${esc(own?.text||'')}</textarea><label class="note-spoiler"><input type="checkbox" name="spoiler" ${own?.scope?'checked':''}> Contains spoilers</label><p class="note-scope">Spoiler scope: ${esc(own?.scope||(get(k).medium==='manga'?'Manga · whole story':'Season '+viewedSection))}</p><button type="submit" class="note-save">Save preview comment <span aria-hidden="true">↗</span></button><small>Local preview only · nothing is posted.</small><p class="note-error" role="status" hidden></p></form></details></section>`;
}
function circleNote(n){return `<article class="circle-note"><div class="note-byline"><b>${esc(n.name)}</b><span>${esc(n.club)}</span></div>${n.scope?`<details class="comment-spoiler"><summary><span>Spoiler · ${esc(n.scope)}</span><span class="reveal-label">Reveal</span><span class="hide-label">Hide</span></summary><p>${esc(n.text)}</p></details>`:`<p>${esc(n.text)}</p>`}</article>`;}
dialog.addEventListener('submit',e=>{
 if(!e.target.matches('[data-note-form]'))return;e.preventDefault();
 const form=e.target,text=form.elements.note.value.trim(),error=form.querySelector('.note-error');
 if(!text||text.length>500){error.hidden=false;error.textContent='Write a comment of 1–500 characters.';return;}
 const fail=document.querySelector('#fail');if(fail.checked){fail.checked=false;error.hidden=false;error.textContent='Could not save. Your draft is still here—try again.';return;}
 const old=localNotes.get(selected),scope=form.elements.spoiler.checked?(old?.scope||form.querySelector('.note-scope').textContent.replace('Spoiler scope: ','')):null;
 localNotes.set(selected,{text,scope});dialog.querySelector('#detail-circle').outerHTML=clubRoom(selected);
 dialog.querySelector('.circle-compose summary').focus({preventScroll:true});toast('Saved in this preview only.');
});

function detailUnits(k,n,expanded=false){
 const manga=get(k).medium==='manga',current=!seriesSections[k]||n===seriesSections[k].current;
 const tracked=!!state[k]&&scenario!=='new'&&current;
 const start=tracked?Math.max(1,state[k].n):1;
 const limit=tracked&&state[k].max!=null?Math.min(expanded?12:3,Math.max(0,state[k].max-start+1)):(expanded?8:3);
 const numbers=Array.from({length:limit},(_,i)=>start+i);if(tracked&&!capped(k)){const next=numbers.indexOf(state[k].n+1);if(next>0)numbers.unshift(numbers.splice(next,1)[0]);}
 return `<div class="unit-list">${numbers.map(number=>{const done=tracked&&number<=state[k].n,next=tracked&&number===state[k].n+1,unit=manga?'Chapter':'Episode';return `<article class="unit-item${next?' is-next':''}${done?' is-finished':''}" data-unit="${number}"><details class="unit-row"><summary>${next?`<span class="next-art" aria-hidden="true">${art(k)}</span>`:`<span class="unit-index">${String(number).padStart(2,'0')}</span>`}<span class="unit-copy">${next?'<small class="next-label">UP NEXT</small>':''}<b>${unit} ${number}</b>${!next?`<small>${done?'Completed':'Tap for details'}</small>`:''}</span><span class="unit-state" aria-hidden="true">${done?'✓':next?'':'⌄'}</span></summary><p>${unit} synopsis unavailable in this preview.</p></details>${next?`<button class="unit-complete" data-step="${k}" aria-label="Complete ${unit.toLowerCase()} ${number} of ${esc(get(k).title)}"><span class="key-cap" aria-hidden="true">${actionIcon(false)}</span></button>`:''}</article>`}).join('')}</div>`;
}
function refreshUnits(k,expanded,keepPosition=false){
 const list=dialog.querySelector('.unit-list');if(!list)return;
 const focusNext=!!document.activeElement?.closest('.unit-complete');
 const before=list.getBoundingClientRect().top,oldHeight=list.offsetHeight;
 const openUnits=[...list.querySelectorAll('details[open]')].map(el=>el.closest('[data-unit]').dataset.unit);
 list.outerHTML=detailUnits(k,viewedSection,expanded);
 const updated=dialog.querySelector('.unit-list');
 openUnits.forEach(n=>{const row=updated.querySelector(`[data-unit="${n}"] details`);if(row)row.open=true;});
 if(keepPosition){dialog.scrollTop+=updated.getBoundingClientRect().top-before;animate(updated,[{height:oldHeight+'px',overflow:'clip'},{height:updated.offsetHeight+'px',overflow:'clip'}],{duration:230,easing:'cubic-bezier(.2,.8,.25,1)'});}
 if(focusNext)(dialog.querySelector('.unit-complete')||dialog.querySelector('[data-units]'))?.focus({preventScroll:true});
}

function updateDetailStory(k,n){
 const host=dialog.querySelector('.detail-hook');if(!host)return;
 const anime=get(k).medium==='anime',f=detailFixtures[k],section=anime?f?.sections[n]:null,hasSection=!!section?.premise;
 const copy=hasSection?section:f,premise=copy?.premise||(anime?storyCopy(k).premise:storyCopy(k).kind==='MANGA'?'Story overview isn’t available yet.':storyCopy(k).premise);
 host.innerHTML=`<span class="detail-eyebrow">${hasSection?'Season '+n:'Series overview'}</span><h3>${esc(copy?.hook||get(k).vibe)}</h3>${anime?'':`<p>${esc(premise)}</p>`}${anime||copy?.synopsis?`<details class="full-synopsis"><summary>About this ${hasSection?'season':'story'} <span aria-hidden="true">+</span></summary><p>${esc(copy?.synopsis||premise)}</p><span class="expectation">${esc(copy?.lens||'')}</span></details>`:''}`;
}
function renderSectionContent(k,n){
 updateDetailStory(k,n);applyDetailMaterial(k,n);
 const host=dialog.querySelector('#selected-section-content');if(!host)return;
 const t=get(k),manga=t.medium==='manga',f=detailFixtures[k],section=manga?f:f?.sections[n],label=seriesSections[k]?(manga?'Part ':'Season ')+n:(manga?'Reading':'Episodes');
 host.innerHTML=`<section class="selected-edition" aria-label="${label} information">${manga?'':`<div class="edition-heading"><span class="detail-eyebrow">${label}</span><h3>${esc(section?.name||'Your place in the story')}</h3></div>`}<div class="detail-section-head"><h4>${manga?'Chapters':'Episodes'}</h4><small>Preview</small></div>${detailUnits(k,n)}<button class="detail-text-button" data-units aria-expanded="false">${manga?'More chapters':'More episodes'}<span aria-hidden="true">↓</span></button></section>
 ${manga?adaptationGuide(k):''}${!manga&&f?.source?`<section class="source-bridge"><span class="bridge-book" aria-hidden="true"><span>原作</span><i></i></span><div><span class="detail-eyebrow">The original story</span><h4>${esc(f.source.name)}</h4><p>${esc(f.source.by)}</p>${f.source.key?`<button class="source-detail-link" data-related="${f.source.key}">Explore the manga <span aria-hidden="true">→</span></button>`:`<a href="${f.source.url}" target="_blank" rel="noopener noreferrer">Explore the manga <span aria-hidden="true">↗</span></a>`}<small>Season ${n} → manga</small></div><details class="coverage-disclosure"><summary>Where this season meets the manga <span aria-hidden="true">+</span></summary><div class="coverage-points"><div><small>Starts at</small><b>Unverified</b></div><div><small>Ends at</small><b>Unverified</b></div><div><small>Read next</small><b>Unverified</b></div></div><p>Season ${n} chapter boundaries need source verification. This is a season-end guide, not a match for your current episode.</p></details></section>`:''}
 ${section?.songs?`<section class="sound-panel" aria-label="Season ${n} music"><div class="detail-section-head"><h3>The sound of it.</h3><span class="sound-signature" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span></div>${section.songs.map(song=>`<a class="song-row" href="https://open.spotify.com/search/${encodeURIComponent(song[1]+' '+song[2])}" target="_blank" rel="noopener noreferrer" aria-label="Find ${esc(song[1])} by ${esc(song[2])} on Spotify"><span class="song-glyph" aria-hidden="true">${song[3]?`<img src="${esc(song[3])}" alt="">`:`<span>${song[0].startsWith('Opening')?'OP':'ED'}</span>`}</span><span><small>${esc(song[0])}</small><b>${esc(song[1])}</b><span>${esc(song[2])}</span></span><span class="song-arrow" aria-hidden="true">↗</span></a>`).join('')}<p class="music-note">Find on Spotify · track links not yet matched</p></section>`:''}
 ${f?.cast&&(!manga||n===1)?`<section class="detail-cast"><div class="detail-section-head"><h3>The characters.</h3><small>Tap to meet</small></div><div class="portrait-rail">${f.cast.map((c,i)=>`<button class="character-card" data-character="${i}" aria-label="About ${esc(c[0])}" aria-expanded="false"><span class="character-image"><img src="assets/detail-character-${c[1]}.png" alt="${esc(c[0])}" loading="lazy"></span><span>${esc(c[0])}</span></button>`).join('')}</div><div class="character-note" role="status" hidden></div></section>`:''}
 ${section?.credits?`<section class="detail-credits"><h3>Behind the ${manga?'pages':'frames'}.</h3>${section.credits.map(c=>`<div><span>${esc(c[0])}</span><b>${esc(c[1])}</b></div>`).join('')}</section>`:''}
 ${manga&&f?.publisher?`<a class="publisher-link" href="${f.publisher}" target="_blank" rel="noopener noreferrer"><span>Read with the publisher<small>Chapters & availability at VIZ</small></span><span aria-hidden="true">↗</span></a>`:''}`;
 const edition=host.querySelector('.selected-edition');dialog.querySelector('.edition-slot').replaceChildren(edition);
}
function detailContent(k,club=false){
 const t=get(k),tracked=!!state[k]&&scenario!=='new',isManga=t.medium==='manga',f=detailFixtures[k],section=seriesSections[k];
 dialog.dataset.medium=t.medium;dialog.dataset.series=String(!!section);dialog.dataset.rich='true';dialog.setAttribute('aria-label',t.title+' details');
 viewedSection=section?.current||1;dialog.style.setProperty('--selection-center',section?((viewedSection-.5)/section.count*100)+'%':'50%');
 dialog.innerHTML=`<button class="close" aria-label="Close details">×</button><div class="detail-intro"><div class="detail-light" aria-hidden="true">${art(k)}</div><div class="detail-object">${art(k)}</div><div class="detail-heading"><span class="detail-kicker">${isManga?'Manga':'Anime'}</span><h2>${esc(t.title)}</h2><span class="detail-collection">${tracked?(isManga?'Reading':'Watching'):'A new story'}</span></div></div><div class="detail-body"><section class="detail-hook"><h3>${esc(f?.hook||t.vibe)}</h3><p>${esc(f?.premise||storyCopy(k).premise)}</p>${f?`<details class="full-synopsis"><summary>About the story <span aria-hidden="true">+</span></summary><p>${esc(f.synopsis)}</p><span class="expectation">${esc(f.lens)}</span></details>`:''}</section>${scenario!=='new'&&f?.circle?`<a class="circle-jump" href="#detail-circle"><span class="tiny-people" aria-hidden="true">${f.circle.people.map(p=>`<i>${esc(p[0][0])}</i>`).join('')}</span><span>${f.circle.people.length} people in your clubs</span><span aria-hidden="true">↓</span></a>`:''}<div class="season-workspace">${section?seriesOverview(k,tracked):''}<div class="season-content">${tracked?`<div class="detail-progress"><div class="progress-context"><span>${isManga?'Your bookmark':sectionName(k)?sectionName(k)+' progress':'Your progress'}</span><small>${capped(k)?'Caught up':state[k].max?state[k].max+' '+(isManga?'chapters':'episodes')+' in this preview':'Ongoing · total unknown'}</small></div>${step(k)}</div>`:saveButton(k)}<div class="edition-slot"></div></div></div><div id="selected-section-content"></div>${clubRoom(k)}<p class="sample">Design preview · sample progress, groupings & club activity.<br>Editorial descriptors are illustrative. No live tracking.</p><div class="dialog-result" role="status" hidden></div></div>`;
 renderSectionContent(k,viewedSection);
}

function open(k,club=false,overview=false){detailClub=club;selected=k;origin=document.activeElement;const sourceAttr=origin.hasAttribute('data-series')?'data-series':origin.hasAttribute('data-club')?'data-club':'data-detail';const sourceKey=origin.getAttribute(sourceAttr);originLocator=sourceKey?{selector:`[${sourceAttr}="${sourceKey}"]`,index:[...feed.querySelectorAll(`[${sourceAttr}="${sourceKey}"]`)].indexOf(origin)}:null;const sourceImage=origin.querySelector('img')||origin.closest('[data-active],[data-story]')?.querySelector('.cover img,.story-art img,.library-art img');const sourceRect=sourceImage?.getBoundingClientRect();const r=origin.getBoundingClientRect();detailContent(k,club);document.querySelector('#toast').hidden=true;dialog.showModal();dialog.scrollTop=0;if(overview)dialog.querySelector('.series-overview h3')?.focus({preventScroll:true});const d=dialog.getBoundingClientRect();animate(dialog,[{opacity:0,transform:`translate(${(r.x+r.width/2-d.x-d.width/2)*.08}px,${(r.y+r.height/2-d.y-d.height/2)*.08}px) scale(.985)`},{opacity:1,transform:'translate(0,0) scale(1)'}],{duration:200,easing:'ease-out'});if(sourceRect&&!reduced()){const target=dialog.querySelector('.detail-object');const to=target.getBoundingClientRect();animate(target,[{transform:`translate(${(sourceRect.x-to.x)*.12}px,${(sourceRect.y-to.y)*.12}px) scale(.94)`,opacity:.7},{transform:'translate(0,0) scale(1)',opacity:1}],{duration:340,easing:'cubic-bezier(.2,.8,.2,1)'})}}
let closing=false;
async function closeDetail(){if(closing)return;closing=true;const motion=animate(dialog,[{opacity:1,transform:'scale(1) translateY(0)'},{opacity:0,transform:'scale(.985) translateY(4px)'}],{duration:150,easing:'ease-in',fill:'forwards'});if(motion){try{await motion.finished}catch{}}dialog.close();motion?.cancel();closing=false}
dialog.addEventListener('cancel',e=>{e.preventDefault();closeDetail()});
dialog.addEventListener('close',()=>{if(origin?.isConnected)origin.focus({preventScroll:true});else if(originLocator)feed.querySelectorAll(originLocator.selector)[originLocator.index]?.focus({preventScroll:true});else if(selected)feed.querySelector(`[data-detail="${selected}"]`)?.focus({preventScroll:true})});
let pressed=null,cancelledPress=null;
const pressSelector='.upcoming-glance,.library-story,[data-flip-medium],[data-related],[data-guide-choice],.source-detail-link,.note-save,.unit-complete,.character-card,.detail-text-button,.study-season-control,.study-art-marker,.scene-seasons,.progress-seasons,.section-panel,[data-return-current],.season-strip,.day-toggle,.release-row,.release-more,.calendar-more,.club-link,.title-open,.story-open,[data-dismiss-toast],.step,.save,.cover,.arrival button,.spoiler,.club-badge,.announcement-row,.club-title-art,.club-title,.club-secondary,.peek-open,.close,[data-undo]';
function clearPress(cancelled=false){if(!pressed)return;pressed.el.removeAttribute('data-contact');if(cancelled)cancelledPress={el:pressed.el,until:Date.now()+600};pressed=null}
document.addEventListener('pointerdown',e=>{if(e.button!==0)return;const el=e.target.closest(pressSelector);if(!el||el.disabled)return;clearPress();cancelledPress=null;pressed={el,x:e.clientX,y:e.clientY,id:e.pointerId};el.dataset.contact='pressed'});
document.addEventListener('pointermove',e=>{if(pressed&&pressed.id===e.pointerId&&Math.hypot(e.clientX-pressed.x,e.clientY-pressed.y)>9)clearPress(true)},{passive:true});
document.addEventListener('pointercancel',()=>clearPress(true));
document.addEventListener('pointerup',e=>{if(pressed&&pressed.id===e.pointerId){const r=pressed.el.getBoundingClientRect();clearPress(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)}});
window.addEventListener('blur',()=>clearPress(true));
document.addEventListener('click',e=>{const b=e.target.closest('button');if(cancelledPress&&Date.now()<cancelledPress.until&&b===cancelledPress.el&&e.detail!==0){e.preventDefault();e.stopImmediatePropagation();cancelledPress=null}},{capture:true});
document.addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;if(b.hasAttribute('data-upcoming')){goToUpcoming();}else if(b.hasAttribute('data-flip-medium')){switchTo(medium==='anime'?'manga':'anime');}else if(b.hasAttribute('data-home-page')){setHomePage(homePage==='home'?'taste':'home');}else if(b.hasAttribute('data-units')){const expanded=b.getAttribute('aria-expanded')!=='true';const parent=b.closest('.selected-edition');refreshUnits(selected,expanded,true);b.setAttribute('aria-expanded',String(expanded));b.innerHTML=(expanded?'Fewer': 'More')+' '+(get(selected).medium==='manga'?'chapters':'episodes')+'<span aria-hidden="true">'+(expanded?'↑':'↓')+'</span>';}else if(b.hasAttribute('data-character')){const note=dialog.querySelector('.character-note'),c=detailFixtures[selected].cast[Number(b.dataset.character)],was=b.getAttribute('aria-expanded')==='true';dialog.querySelectorAll('[data-character]').forEach(el=>el.setAttribute('aria-expanded','false'));b.setAttribute('aria-expanded',String(!was));note.hidden=was;note.innerHTML='<b>'+esc(c[0])+'</b><span>'+esc(c[2])+'</span>';if(!was)animate(note,[{opacity:.4,transform:'translateY(-3px)'},{opacity:1,transform:'translateY(0)'}],{duration:180,easing:'ease-out'});}else if(b.hasAttribute('data-study-reset'))reset();else if(b.dataset.medium){if(Date.now()>suppressClickUntil)switchTo(b.dataset.medium);}else if(b.dataset.section)previewSection(Number(b.dataset.section));else if(b.hasAttribute('data-return-current')){previewSection(seriesSections[selected].current);dialog.querySelector(`[data-section="${seriesSections[selected].current}"]`).focus({preventScroll:true})}else if(b.dataset.series)open(b.dataset.series,false,true);else if(b.dataset.step)mutate(b.dataset.step,'step');else if(b.dataset.save)mutate(b.dataset.save,'save');else if(b.dataset.day)toggleDay(b.dataset.day);else if(b.dataset.moreDay)moreDay(b.dataset.moreDay);else if(b.hasAttribute('data-more-calendar'))moreCalendar();else if(b.dataset.detail)open(b.dataset.detail);else if(b.dataset.club)open(b.dataset.club,true);else if(b.matches('.close'))closeDetail();else if(b.hasAttribute('data-dismiss-toast'))dismissToast(b);else if(b.hasAttribute('data-spoiler')){toggleSpoiler()}else if(b.hasAttribute('data-undo')&&undo){const u=undo;if(u.type==='step')state[u.k].n=u.n;else u.saved?saved.add(u.k):saved.delete(u.k);undo=null;syncActions(u.k);toast('Undone.')}});
selector.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();const m=e.key==='ArrowLeft'?'anime':'manga';switchTo(m);selector.querySelector(`[data-medium="${m}"]`).focus()}});
// Drag across the medium control; a vertical scroll never commits a switch.
let pointer=null;
selector.addEventListener('pointerdown',e=>{if(e.button!==0)return;pointer={x:e.clientX,y:e.clientY,id:e.pointerId,drag:false,cancelled:false};selector.classList.add('contact');});
selector.addEventListener('pointermove',e=>{if(!pointer||e.pointerId!==pointer.id||pointer.cancelled)return;const dx=e.clientX-pointer.x,dy=e.clientY-pointer.y;if(!pointer.drag&&Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx)){pointer.cancelled=true;selector.classList.remove('contact');return}if(!pointer.drag&&Math.abs(dx)>10&&Math.abs(dx)>Math.abs(dy)){pointer.drag=true;selector.setPointerCapture(e.pointerId);selector.classList.add('dragging')}if(pointer.drag){const width=selector.clientWidth/2;const fraction=Math.min(1,Math.max(0,(medium==='anime'?0:1)+dx/width));selector.style.setProperty('--scrub',fraction);}});
function endScrub(e,cancel=false){if(!pointer||e.pointerId!==pointer.id)return;const p=pointer;pointer=null;selector.classList.remove('dragging','contact');selector.style.removeProperty('--scrub');if(selector.hasPointerCapture(e.pointerId))selector.releasePointerCapture(e.pointerId);if(p.cancelled||cancel)suppressClickUntil=Date.now()+350;if(p.drag){suppressClickUntil=Date.now()+350;if(!cancel&&Math.abs(e.clientX-p.x)>30)switchTo(e.clientX>p.x?'manga':'anime')}}
window.addEventListener('blur',()=>{if(pointer)endScrub({pointerId:pointer.id},true)});
selector.addEventListener('pointerup',e=>endScrub(e));selector.addEventListener('pointercancel',e=>endScrub(e,true));
document.querySelector('#scenario').addEventListener('change',e=>{scenario=e.target.value;reset();if(scenario==='quiet'){Object.values(state).forEach(s=>{if(s.max!==null)s.n=s.max});render()}phone.scrollTop=0});document.querySelector('#reset').addEventListener('click',()=>{scenario='busy';document.querySelector('#scenario').value='busy';reset();phone.scrollTop=0});reset();
const initialScenario=new URLSearchParams(location.search).get('scenario');
if(phone.dataset.reading&&['busy','full','quiet','new','undated'].includes(initialScenario)){scenario=initialScenario;document.querySelector('#scenario').value=scenario;reset();if(scenario==='quiet'){Object.values(state).forEach(s=>{if(s.max!==null)s.n=s.max});render()}}
const initialDetail=new URLSearchParams(location.search).get('detail');if(initialDetail&&get(initialDetail)){if(get(initialDetail).medium!==medium)switchTo(get(initialDetail).medium);open(initialDetail);}
// Page gesture is separate from the Anime/Manga control and horizontal rails.
let pageSwipe=null;
phone.addEventListener('pointerdown',e=>{if(e.button!==0||e.target.closest('button,a,input,select,.selector,.portrait-rail,.section-panels'))return;pageSwipe={x:e.clientX,y:e.clientY,id:e.pointerId};});
phone.addEventListener('pointerup',e=>{if(!pageSwipe||e.pointerId!==pageSwipe.id)return;const dx=e.clientX-pageSwipe.x,dy=e.clientY-pageSwipe.y;pageSwipe=null;if(Math.abs(dx)>85&&Math.abs(dx)>Math.abs(dy)*2){if(dx>0&&homePage==='home')setHomePage('taste');else if(dx<0&&homePage==='taste')setHomePage('home');}});
phone.addEventListener('pointercancel',()=>pageSwipe=null);

})();
