(()=>{'use strict';
const catalog=window.JOURNAL_CATALOG, get=k=>catalog.find(t=>t.key===k), esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const keys={anime:['anime-1','anime-0','anime-2','anime-3','anime-22','anime-12'],manga:['manga-0','manga-1','manga-2','manga-3','manga-13','manga-14']},fresh={anime:['anime-15','anime-16'],manga:['manga-16','manga-23']};
// Illustration-only grouping, not verified catalogue season counts or production mappings.
// Omitted titles intentionally have no invented section hierarchy.
const seriesSections={
 'anime-0':{kind:'season',count:4,current:2},'anime-1':{kind:'season',count:4,current:1},
 'anime-2':{kind:'season',count:2,current:2},'anime-22':{kind:'season',count:3,current:2},
 'manga-0':{kind:'part',count:2,current:1}
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
function seriesOverview(k){
 const section=seriesSections[k];if(!section)return '';viewedSection=section.current;
 const label=section.kind==='season'?'Season':'Part';
 return `<section class="series-overview" aria-label="${label==='Season'?'Seasons':'Parts'} of ${esc(get(k).title)}"><div class="series-overview-heading"><h3 tabindex="-1">${label==='Season'?'Seasons':'Parts'}</h3><small>${section.count} in this story</small></div><div class="section-panels" role="group" aria-label="Browse ${label.toLowerCase()}s">${Array.from({length:section.count},(_,i)=>`<button class="section-panel${i+1===section.current?' is-resume':''}" data-section="${i+1}" aria-pressed="${i+1===section.current}" aria-label="View ${label.toLowerCase()} ${i+1}${i+1===section.current?', current '+(get(k).medium==='anime'?'season':'part'):''}"><span class="panel-index" aria-hidden="true">${i+1}</span><span class="panel-foot" aria-hidden="true">${i+1===section.current?'Current':'<span class="panel-rule"></span>'}</span></button>`).join('')}</div><div class="section-status" role="status" aria-live="polite"><span data-section-name>${label} ${section.current}</span><span data-section-state>${currentSectionProgress(k)}</span></div><div class="section-unknown" hidden><p>Progress unknown.</p><button data-return-current>Back to ${label.toLowerCase()} ${section.current}<span aria-hidden="true">↗</span></button></div></section>`;
}
function previewSection(n){
 const section=seriesSections[selected];if(!section||n<1||n>section.count)return;
 viewedSection=n;const current=n===section.current,label=section.kind==='season'?'Season':'Part';
 dialog.querySelectorAll('[data-section]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.section)===n)));
 dialog.querySelector('[data-section-name]').textContent=label+' '+n;
 dialog.querySelector('[data-section-state]').textContent=current?currentSectionProgress(selected):'Preview';
 dialog.querySelector('.section-unknown').hidden=current;dialog.querySelector('.detail-progress').hidden=!current;
 animate(dialog.querySelector('.section-status'),[{opacity:.45,transform:'translateY(3px)'},{opacity:1,transform:'translateY(0)'}],{duration:180,easing:'ease-out'});
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
let medium='anime',scenario='busy',state={},saved=new Set(),undo=null,selected=null,origin=null,originLocator=null,spoilers=new Set(),detailClub=false,viewedSection=null,openDays=new Set(['date-0']),expandedDays=new Set(),calendarLimit=4,suppressClickUntil=0,lastAction=null;
try{medium=localStorage.getItem('kuro-instrument-medium')==='manga'?'manga':'anime'}catch{}
if(seasonStudy)medium='anime';
function reset(){state={};for(const m of ['anime','manga'])keys[m].forEach((k,i)=>state[k]={n:m==='anime'?[4,7,6,11,3,8][i]:[24,8,16,12,5,40][i],max:m==='anime'?[5,8,9,37,12,64][i]:[25,9,21,null,null,null][i]});saved.clear();spoilers.clear();undo=null;lastAction=null;openDays=new Set(['date-0']);expandedDays.clear();calendarLimit=4;document.querySelector('#fail').checked=false;document.querySelector('#toast').hidden=true;render()}
function capped(k){return state[k].max!==null&&state[k].n>=state[k].max}
function art(k){return `<img src="${get(k).cover}" alt="${esc(get(k).title)}" draggable="false">`}
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
const artwork={
 'anime-1':{focus:'55% 50%',tone:'#28484b'},
 'anime-0':{focus:'50% 50%',tone:'#465471'},
 'anime-15':{focus:'50% 48%',tone:'#42627c'}
};
function sceneArt(k){return `<img src="${get(k).banner||get(k).cover}" alt="${esc(get(k).title)}" draggable="false" style="object-position:${artwork[k]?.focus||'50% 50%'}">`}
function clubShortcut(k){return `<button class="club-link" data-club="${k}" aria-label="See Sunday Club activity for ${esc(get(k).title)}"><span class="club-initial" aria-hidden="true">M</span><span>Mina + Jules</span><span aria-hidden="true">›</span></button>`}
// Titles open details; artwork season markers open the full season overview.
function cardTitle(k){return `<button class="title-open" data-detail="${k}" aria-label="View ${esc(get(k).title)}">${esc(get(k).title)}</button>`}
// Selected design: the current season sits on the cover; progress stays separate.
function compactTitle(k,i,compareNumbers=false){
 const title=medium==='anime'?`<button class="title-open" data-detail="${k}" aria-label="View ${esc(get(k).title)}">${esc(get(k).title)}</button>`:cardTitle(k);
 const marker=medium==='anime'&&seriesSections[k]&&!compareNumbers;
 const target=marker?`data-series="${k}" aria-label="${esc(get(k).title)}: ${sectionName(k)} of ${seriesSections[k].count}. View seasons"`:`data-detail="${k}" aria-label="Open ${esc(get(k).title)}"`;
 return `<article class="carry-card" data-active="${k}" data-slot="${i}"><button class="cover" ${target}>${art(k)}${marker?artworkSeasonMarker(k,true):''}</button><h2>${title}</h2>${step(k,compareNumbers&&medium==='anime')}${medium==='manga'?seasonStrip(k,true):''}${medium==='manga'?mangaContext(k,true):''}</article>`;
}
function active(list){
 const lead=list.slice(0,2).map((k,i)=>medium==='anime'?`<div class="scene-unit" data-active="${k}" data-slot="${i}"><article class="scene-card" style="--scene-tone:${artwork[k].tone}"><div class="study-image"><button class="cover scene-window" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${sceneArt(k)}</button>${artworkSeasonMarker(k)}</div><div class="scene-caption"><div class="scene-title"><h2>${cardTitle(k)}</h2></div>${step(k)}</div><div class="scene-context">${i===1?clubShortcut(k):`<span class="availability" data-availability="${k}">${availability(k)}</span>`}</div></article></div>`:`<article class="reading-card" data-active="${k}" data-slot="${i}"><div class="reading-art"><button class="cover" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${art(k)}</button></div><div class="reading-caption"><h2>${cardTitle(k)}</h2>${step(k)}</div>${mangaContext(k)}${seasonStrip(k)||'<span class="section-placeholder" aria-hidden="true"></span>'}</article>`).join('');
 return `<div class="${medium==='anime'?'scene-stack':'reading-spread'}">${lead}</div><div class="rotation-heading"><h2>${medium==='anime'?'Also watching':'On your shelf'}</h2><span>4 titles</span></div><div class="carry-grid">${list.slice(2).map((k,i)=>compactTitle(k,i+2)).join('')}</div>`;
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

function saveButton(k){return `<button class="save" data-save="${k}" aria-label="${saved.has(k)?'Remove '+esc(get(k).title)+' from your list':'Plan to '+(medium==='anime'?'watch ':'read ')+esc(get(k).title)}" aria-pressed="${saved.has(k)}"><span>${saved.has(k)?'Planned':medium==='anime'?'Plan to watch':'Plan to read'}</span><span class="save-mark" aria-hidden="true"><svg viewBox="0 0 20 24"><path d="M4 3h12v18l-6-4-6 4z"/>${saved.has(k)?'<path class="bookmark-tick" d="M7 9l2 2 4-4"/>':''}</svg></span></button>`}
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
function schedule(){const groups=releaseGroups(),total=groups.reduce((n,g)=>n+g.events.length,0);return `<section class="coming-up" aria-label="Upcoming from your list"><div class="section-head"><h2>Coming up.</h2><small>${total?total+' releases · '+(scenario==='full'?'6 weeks':'7 days'):'From your list'}</small></div><div class="release-calendar">${calendarBody()}</div></section>`}
function toggleDay(id){const opened=!openDays.has(id);opened?openDays.add(id):openDays.delete(id);feed.querySelector(`[data-day="${id}"]`).setAttribute('aria-expanded',String(opened));feed.querySelector('#body-'+id).hidden=!opened;}
function moreDay(id){expandedDays.has(id)?expandedDays.delete(id):expandedDays.add(id);const group=releaseGroups().find(g=>g.id===id),body=feed.querySelector('#body-'+id);body.innerHTML=dayBody(group);body.querySelector('[data-more-day]')?.focus({preventScroll:true});}
function moreCalendar(){const groups=releaseGroups(),next=groups.slice(calendarLimit,calendarLimit+4),button=feed.querySelector('[data-more-calendar]');feed.querySelector('.dated-groups').insertAdjacentHTML('beforeend',next.map(dayGroup).join(''));calendarLimit+=next.length;const remaining=groups.length-calendarLimit;if(remaining)button.innerHTML=`Next ${Math.min(4,remaining)} dates <span>${groups.slice(calendarLimit,calendarLimit+4).reduce((n,g)=>n+g.events.length,0)} releases ↓</span>`;else button.remove();feed.querySelector(`[data-day="${next[0].id}"]`)?.focus({preventScroll:true});}
function clubNote(){const k=keys[medium][3],other=keys[medium][1];return `<section class="club-section club-room" aria-label="Sunday Club activity"><div class="club-masthead"><span class="club-seal" aria-hidden="true"><svg viewBox="0 0 40 40"><path d="M9 9h22v22H9zM14 14h12v12H14zM4 20h10M26 20h10M20 4v10M20 26v10"/></svg></span><div><span class="club-kicker">YOUR PRIVATE CLUB</span><h2>Sunday Club</h2></div><span class="member-stack" aria-label="Members Mina, Jules and Ari"><span>M</span><span>J</span><span>A</span></span></div><div class="club-note"><div class="club-entry"><button class="club-title-art" data-club="${k}" aria-label="See club activity for ${esc(get(k).title)}">${art(k)}</button><div class="club-copy"><div class="person-line"><b>Mina</b><small>2h ago</small></div><p>“Just one more.<br>Famous last words.”</p><button class="club-title" data-club="${k}">Finished ${esc(get(k).title)} <span aria-hidden="true">›</span></button></div></div><button class="spoiler" data-spoiler aria-expanded="${spoilers.has(medium)}" aria-controls="club-spoiler"><span>${spoilers.has(medium)?'Hide spoiler':'Mina’s thought on the ending'}</span><span class="spoiler-key" aria-hidden="true">⌄</span></button><p id="club-spoiler" class="spoiler-content" ${spoilers.has(medium)?'':'hidden'}>Sample spoiler: that quiet final scene changes the opening.</p></div><button class="club-secondary" data-club="${other}">${art(other)}<span><b>Jules started</b><span>${esc(get(other).title)}</span></span><span class="row-arrow" aria-hidden="true">›</span></button><div class="club-room-footer"><span>Shared stories. Your people.</span><span>2 updates</span></div></section>`}
function updateOpening(){phone.dataset.medium=medium;const available=scenario==='new'?0:medium==='manga'?keys.manga.reduce((total,k)=>total+newChapterCount(k),0):keys.anime.slice(0,2).filter(k=>!capped(k)).length;document.querySelector('.opening-eyebrow').textContent=scenario==='new'?'YOUR COLLECTION':medium==='anime'?'NOW WATCHING':'NOW READING';document.querySelector('.opening-copy h1').textContent=scenario==='new'?'Begin here.':available?available+' new '+(medium==='anime'?'episode':'chapter')+(available===1?'':'s'):medium==='anime'?'Keep watching.':'Keep reading.';selector.dataset.medium=medium;selector.querySelectorAll('button[data-medium]').forEach(b=>{b.setAttribute('aria-pressed',String(b.dataset.medium===medium));b.querySelector('.mode-meta').textContent=scenario==='new'?'Start here':b.dataset.medium==='anime'?'6 watching':'6 reading'});}
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
 feed.innerHTML=`<div class="season-study"><header class="study-heading"><div><a href="instrument.html">KURO / HOME STUDY</a><h1>A name for the numbers.</h1><p>Three directions. Large cards + compact cards.</p></div><button data-study-reset>Reset examples ↺</button></header><div class="study-grid">${variants.map(([style,name,note])=>`<section class="study-option" data-label-style="${style}" aria-label="${name}"><header class="study-option-heading"><h2>${name}</h2><p>${note}</p></header><div class="study-surface"><div class="study-size-label">NOW WATCHING</div><div class="scene-unit" data-active="${k}"><article class="scene-card" style="--scene-tone:${artwork[k].tone}"><div class="study-image"><button class="cover scene-window" data-detail="${k}" aria-label="Open ${esc(get(k).title)}">${sceneArt(k)}</button>${style==='artwork'?artworkSeasonMarker(k):''}</div><div class="scene-caption"><div class="scene-title"><h2>${cardTitle(k)}</h2></div>${step(k)}</div><div class="scene-context">${clubShortcut(k)}</div>${style==='artwork'?'':studySeasonButton(k,style)}</article></div><div class="rotation-heading"><h2>Also watching</h2></div><div class="carry-grid">${['anime-2','anime-22'].map((key,i)=>studyCompact(key,i,style)).join('')}</div></div></section>`).join('')}</div><footer class="study-footnote">Tap any season treatment to open the existing detail design. Illustrative season counts · browser study only.</footer></div>`;
}

function render(){if(seasonStudy){renderSeasonStudy();return}updateOpening();feed.dataset.medium=medium;if(scenario==='new'){feed.innerHTML=newTitles();observeHome();return}feed.innerHTML=`<h1 class="sr-only">${medium==='anime'?'Currently watching':'Currently reading'}</h1>${scenario==='quiet'?'<div class="quiet">Nothing new today. Stay at your own pace.</div>':''}<section class="activity-stage" aria-label="${medium==='anime'?'Currently watching':'Currently reading'}">${active(keys[medium])}<div class="stage-caption" aria-hidden="true"><span></span><span>↓</span></div></section><div class="paper-feed">${newTitles()}${schedule()}${clubNote()}</div>`;observeHome()}
const reduced=()=>matchMedia('(prefers-reduced-motion: reduce)').matches;
function animate(el,frames,options){if(!el||reduced())return;const motion=el.animate(frames,options);homeMotions.add(motion);motion.finished.finally(()=>homeMotions.delete(motion)).catch(()=>{});return motion}
// One subtle entrance per section and medium; scrolling or saving never replays it.
const seenSections=new Set();
const entrances=new IntersectionObserver(entries=>{
 for(const entry of entries){if(!entry.isIntersecting)continue;const el=entry.target,key=medium+':'+el.className;entrances.unobserve(el);if(seenSections.has(key))continue;seenSections.add(key);
  const frames=medium==='anime'?[{opacity:.8,transform:'translateY(9px)'},{opacity:1,transform:'translateY(0)'}]:[{opacity:.85,clipPath:'inset(0 0 7% 0)'},{opacity:1,clipPath:'inset(0 0 0 0)'}];
  el.querySelectorAll('.story-art img,.release-art img,.club-title-art img').forEach(image=>animate(image,frames,{duration:medium==='anime'?380:260,easing:'cubic-bezier(.2,.75,.25,1)'}));
 }
},{root:phone,threshold:.12});
function observeHome(){entrances.disconnect();feed.querySelectorAll('.coming-up,.club-section,.suggestions').forEach(el=>entrances.observe(el));updateScroll()}
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
 feed.querySelectorAll('[data-slot] .cover img').forEach(el=>{
  if(el.getBoundingClientRect().top>phone.getBoundingClientRect().bottom)return;
  animate(el,[{opacity:.65,clipPath:'inset(0 0 5% 0)'},{opacity:1,clipPath:'inset(0 0 0 0)'}],{duration:320,easing:'cubic-bezier(.2,.8,.25,1)'});
 });
 feed.querySelectorAll('.scene-title,.reading-caption h2,.carry-card h2').forEach(el=>animate(el,[{opacity:.65},{opacity:1}],{duration:240,easing:'ease-out'}));
}
function toast(message,withUndo=false){const box=dialog.open?dialog.querySelector('.dialog-result'):document.querySelector('#toast');if(!box)return;const restoreFocus=box.contains(document.activeElement);box.hidden=false;box.innerHTML=`<span>${esc(message)}</span><span class="toast-actions">${withUndo?'<button data-undo>Undo</button>':''}<button data-dismiss-toast aria-label="Dismiss notification"><span aria-hidden="true">×</span></button></span>`;if(restoreFocus)box.querySelector(withUndo?'[data-undo]':'[data-dismiss-toast]')?.focus({preventScroll:true})}
function dismissToast(button){button.closest('[role="status"]').hidden=true;if(!lastAction)return;const root=dialog.open?dialog:feed;const target=root.querySelector(`[data-${lastAction.type}="${lastAction.k}"]`);(target&&!target.disabled?target:root.querySelector(`[data-detail="${lastAction.k}"]`))?.focus({preventScroll:true})}
// Patch only the affected state. Covers, scroll, section entrances and neighbouring controls keep their DOM identity.
function syncActions(k){
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
 if(dialog.open&&selected===k&&state[k])dialog.querySelector('.progress-context small').textContent=done?'Caught up':state[k].max?state[k].max+' '+(t.medium==='anime'?'episodes':'chapters')+' available':'Ongoing · total unknown';
 updateOpening();
}
function mutate(k,type){
 if(type==='step'&&capped(k))return;lastAction={k,type};
 if(document.querySelector('#fail').checked){document.querySelector('#fail').checked=false;const failed=(dialog.open?dialog:feed).querySelector(`[data-${type}="${k}"]`);failed?.setAttribute('data-feedback','failed');toast(type==='step'?'Not saved. Your progress is unchanged.':'Not saved. Your list is unchanged.');return}
 undo={k,type,n:state[k]?.n,saved:saved.has(k)};
 if(type==='step')state[k].n++;else saved.has(k)?saved.delete(k):saved.add(k);
 syncActions(k);
 document.querySelectorAll(`[data-${type}="${k}"]`).forEach(el=>{el.dataset.feedback='saved';animate(el.querySelector('.key-cap,.save-mark'),[{transform:'scale(.96)'},{transform:'scale(1)'}],{duration:160,easing:'cubic-bezier(.2,.7,.3,1)'})});
 if(type==='step'){
  document.querySelectorAll(`[data-count="${k}"]`).forEach(el=>animate(el,[{opacity:.55,transform:'translateY(2px)'},{opacity:1,transform:'translateY(0)'}],{duration:220,easing:'ease-out'}));
  if(state[k].max)document.querySelectorAll(`[data-trace="${k}"]`).forEach(el=>animate(el,[{width:(undo.n/state[k].max*100)+'%'},{width:(state[k].n/state[k].max*100)+'%'}],{duration:280,easing:'cubic-bezier(.22,.8,.24,1)'}));
 }
 toast(type==='step'?(capped(k)?'Caught up.':'Progress saved.'):(saved.has(k)?'Added to your list.':'Removed from your list.'),true);
}
function toggleSpoiler(){const shown=!spoilers.has(medium);shown?spoilers.add(medium):spoilers.delete(medium);const button=feed.querySelector('[data-spoiler]'),content=feed.querySelector('#club-spoiler');button.setAttribute('aria-expanded',String(shown));button.firstElementChild.textContent=shown?'Hide spoiler':'Mina’s thought on the ending';content.hidden=!shown;if(shown)animate(content,[{opacity:.6},{opacity:1}],{duration:180,easing:'ease-out'})}
function detailContent(k,club=false){const t=get(k),tracked=state[k]&&scenario!=='new',isManga=t.medium==='manga',readers=club&&origin?.dataset.clubContext==='readers'?mangaActivity[k]?.readers:null;dialog.dataset.medium=t.medium;dialog.dataset.series=String(!!(tracked&&!club&&seriesSections[k]));dialog.innerHTML=`<button class="close" aria-label="Close details">×</button><div class="detail-intro"><div class="detail-object">${art(k)}</div><div class="detail-heading"><span class="detail-kicker">${isManga?'Manga':'Anime'}${tracked?' · In your collection':''}</span><h2>${esc(t.title)}</h2>${tracked?'':`<p>${esc(storyCopy(k).premise)}</p>`}</div></div><div class="detail-body">${tracked&&!club?seriesOverview(k):''}${tracked?`<div class="detail-progress"><div class="progress-context"><span>${sectionName(k)?sectionName(k)+' progress':'Your progress'}</span><small>${capped(k)?'Caught up':state[k].max?state[k].max+' '+(isManga?'chapters':'episodes')+' available':'Ongoing · total unknown'}</small></div>${step(k)}</div>`:saveButton(k)}${readers?.length?`<div class="detail-club"><div class="person-line"><span class="person-avatar" aria-hidden="true">${readers[0][0]}</span><b>${esc(readers.join(' + '))} reading</b><small>Sunday Club</small></div></div>`:club?`<div class="detail-club"><div class="person-line"><span class="person-avatar" aria-hidden="true">${k===keys[medium][3]?'M':'J'}</span><b>${k===keys[medium][3]?'Mina finished this':'Jules started this'}</b><small>Sunday Club</small></div>${k===keys[medium][3]?'<p>“Just one more. Famous last words.”</p>':''}</div>`:''}<div class="dialog-result" role="status" hidden></div><p class="sample">Illustrative account · local preview</p></div>`}
function open(k,club=false,overview=false){detailClub=club;selected=k;origin=document.activeElement;const sourceAttr=origin.hasAttribute('data-series')?'data-series':origin.hasAttribute('data-club')?'data-club':'data-detail';const sourceKey=origin.getAttribute(sourceAttr);originLocator=sourceKey?{selector:`[${sourceAttr}="${sourceKey}"]`,index:[...feed.querySelectorAll(`[${sourceAttr}="${sourceKey}"]`)].indexOf(origin)}:null;const sourceImage=origin.querySelector('img')||origin.closest('[data-active],[data-story]')?.querySelector('.cover img,.story-art img');const sourceRect=sourceImage?.getBoundingClientRect();const r=origin.getBoundingClientRect();detailContent(k,club);document.querySelector('#toast').hidden=true;dialog.showModal();if(overview)dialog.querySelector('.series-overview h3')?.focus({preventScroll:true});const d=dialog.getBoundingClientRect();animate(dialog,[{opacity:0,transform:`translate(${(r.x+r.width/2-d.x-d.width/2)*.08}px,${(r.y+r.height/2-d.y-d.height/2)*.08}px) scale(.985)`},{opacity:1,transform:'translate(0,0) scale(1)'}],{duration:200,easing:'ease-out'});if(sourceRect&&!reduced()){const target=dialog.querySelector('.detail-object');const to=target.getBoundingClientRect();animate(target,[{transform:`translate(${(sourceRect.x-to.x)*.12}px,${(sourceRect.y-to.y)*.12}px) scale(.94)`,opacity:.7},{transform:'translate(0,0) scale(1)',opacity:1}],{duration:340,easing:'cubic-bezier(.2,.8,.2,1)'})}}
let closing=false;
async function closeDetail(){if(closing)return;closing=true;const motion=animate(dialog,[{opacity:1,transform:'scale(1) translateY(0)'},{opacity:0,transform:'scale(.985) translateY(4px)'}],{duration:150,easing:'ease-in',fill:'forwards'});if(motion){try{await motion.finished}catch{}}dialog.close();motion?.cancel();closing=false}
dialog.addEventListener('cancel',e=>{e.preventDefault();closeDetail()});
dialog.addEventListener('close',()=>{if(origin?.isConnected)origin.focus({preventScroll:true});else if(originLocator)feed.querySelectorAll(originLocator.selector)[originLocator.index]?.focus({preventScroll:true});else if(selected)feed.querySelector(`[data-detail="${selected}"]`)?.focus({preventScroll:true})});
let pressed=null,cancelledPress=null;
const pressSelector='.study-season-control,.study-art-marker,.scene-seasons,.progress-seasons,.section-panel,[data-return-current],.season-strip,.day-toggle,.release-row,.release-more,.calendar-more,.club-link,.title-open,.story-open,[data-dismiss-toast],.step,.save,.cover,.arrival button,.spoiler,.club-badge,.announcement-row,.club-title-art,.club-title,.club-secondary,.peek-open,.close,[data-undo]';
function clearPress(cancelled=false){if(!pressed)return;pressed.el.removeAttribute('data-contact');if(cancelled)cancelledPress={el:pressed.el,until:Date.now()+600};pressed=null}
document.addEventListener('pointerdown',e=>{if(e.button!==0)return;const el=e.target.closest(pressSelector);if(!el||el.disabled)return;clearPress();cancelledPress=null;pressed={el,x:e.clientX,y:e.clientY,id:e.pointerId};el.dataset.contact='pressed'});
document.addEventListener('pointermove',e=>{if(pressed&&pressed.id===e.pointerId&&Math.hypot(e.clientX-pressed.x,e.clientY-pressed.y)>9)clearPress(true)},{passive:true});
document.addEventListener('pointercancel',()=>clearPress(true));
document.addEventListener('pointerup',e=>{if(pressed&&pressed.id===e.pointerId){const r=pressed.el.getBoundingClientRect();clearPress(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)}});
window.addEventListener('blur',()=>clearPress(true));
document.addEventListener('click',e=>{const b=e.target.closest('button');if(cancelledPress&&Date.now()<cancelledPress.until&&b===cancelledPress.el&&e.detail!==0){e.preventDefault();e.stopImmediatePropagation();cancelledPress=null}},{capture:true});
document.addEventListener('click',e=>{const b=e.target.closest('button');if(!b)return;if(b.hasAttribute('data-study-reset'))reset();else if(b.dataset.medium){if(Date.now()>suppressClickUntil)switchTo(b.dataset.medium);}else if(b.dataset.section)previewSection(Number(b.dataset.section));else if(b.hasAttribute('data-return-current')){previewSection(seriesSections[selected].current);dialog.querySelector(`[data-section="${seriesSections[selected].current}"]`).focus({preventScroll:true})}else if(b.dataset.series)open(b.dataset.series,false,true);else if(b.dataset.step)mutate(b.dataset.step,'step');else if(b.dataset.save)mutate(b.dataset.save,'save');else if(b.dataset.day)toggleDay(b.dataset.day);else if(b.dataset.moreDay)moreDay(b.dataset.moreDay);else if(b.hasAttribute('data-more-calendar'))moreCalendar();else if(b.dataset.detail)open(b.dataset.detail);else if(b.dataset.club)open(b.dataset.club,true);else if(b.matches('.close'))closeDetail();else if(b.hasAttribute('data-dismiss-toast'))dismissToast(b);else if(b.hasAttribute('data-spoiler')){toggleSpoiler()}else if(b.hasAttribute('data-undo')&&undo){const u=undo;if(u.type==='step')state[u.k].n=u.n;else u.saved?saved.add(u.k):saved.delete(u.k);undo=null;syncActions(u.k);toast('Undone.')}});
selector.addEventListener('keydown',e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();const m=e.key==='ArrowLeft'?'anime':'manga';switchTo(m);selector.querySelector(`[data-medium="${m}"]`).focus()}});
// Drag across the medium control; a vertical scroll never commits a switch.
let pointer=null;
selector.addEventListener('pointerdown',e=>{if(e.button!==0)return;pointer={x:e.clientX,y:e.clientY,id:e.pointerId,drag:false,cancelled:false};selector.classList.add('contact');});
selector.addEventListener('pointermove',e=>{if(!pointer||e.pointerId!==pointer.id||pointer.cancelled)return;const dx=e.clientX-pointer.x,dy=e.clientY-pointer.y;if(!pointer.drag&&Math.abs(dy)>12&&Math.abs(dy)>Math.abs(dx)){pointer.cancelled=true;selector.classList.remove('contact');return}if(!pointer.drag&&Math.abs(dx)>10&&Math.abs(dx)>Math.abs(dy)){pointer.drag=true;selector.setPointerCapture(e.pointerId);selector.classList.add('dragging')}if(pointer.drag){const width=selector.clientWidth/2;const fraction=Math.min(1,Math.max(0,(medium==='anime'?0:1)+dx/width));selector.style.setProperty('--scrub',fraction);}});
function endScrub(e,cancel=false){if(!pointer||e.pointerId!==pointer.id)return;const p=pointer;pointer=null;selector.classList.remove('dragging','contact');selector.style.removeProperty('--scrub');if(selector.hasPointerCapture(e.pointerId))selector.releasePointerCapture(e.pointerId);if(p.cancelled||cancel)suppressClickUntil=Date.now()+350;if(p.drag){suppressClickUntil=Date.now()+350;if(!cancel&&Math.abs(e.clientX-p.x)>30)switchTo(e.clientX>p.x?'manga':'anime')}}
window.addEventListener('blur',()=>{if(pointer)endScrub({pointerId:pointer.id},true)});
selector.addEventListener('pointerup',e=>endScrub(e));selector.addEventListener('pointercancel',e=>endScrub(e,true));
document.querySelector('#scenario').addEventListener('change',e=>{scenario=e.target.value;reset();if(scenario==='quiet'){Object.values(state).forEach(s=>{if(s.max!==null)s.n=s.max});render()}phone.scrollTop=0});document.querySelector('#reset').addEventListener('click',()=>{scenario='busy';document.querySelector('#scenario').value='busy';reset();phone.scrollTop=0});reset();
})();
