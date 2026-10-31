#!/usr/bin/env python3
"""Capture current SwiftUI source in an isolated, disposable preview build."""
import argparse, hashlib, json, pathlib, shutil, subprocess, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=pathlib.Path('/tmp/kuro-screen-canvas'); SNAP=OUT/'source'; BUNDLE='com.Kuro.canvaspreview'
SCREENS=[('welcome','Welcome'),('signin','Sign in'),('signup','Create account'),('onboarding','Onboarding'),('taste','Taste'),('discover','Discover'),('browse','Browse'),('collection','Collection · anonymous'),('clubs','Clubs · anonymous'),('search','Search'),('profile','Profile · anonymous'),('concierge','Concierge'),('createclub','Create club'),('joinclub','Join club'),('rail','Create club shelf'),('poll','Create poll')]
SCREENS += [('anime','Anime detail'),('manga','Manga detail'),('addanime','Add anime to list'),('addmanga','Add manga to list'),('episodes','Episodes'),('chapters','Chapters'),('filters','Browse filters'),('services','Streaming preferences'),('genre','Genre hub')]
SCREENS += [('onboarding'+str(i), 'Onboarding · '+str(i+1)) for i in range(1,5)] + [('genie','Authentication · Genie'),('browse-manga','Browse · Manga'),('taste-manga','Taste · Manga')]
SCREENS += [(k,t) for k,t in [('character','Character detail'),('staff','Staff detail'),('studio','Studio detail'),('author','Author detail'),('credits','All credits')]]
SCREENS += [('club-'+k, 'Club · '+k+' · sample') for k in ['rails','active','polls','settings']] + [('railitem','Add title to club shelf'),('import','AniList import'),('verdict','Quick verdict'),('cast','Character directory')]
SCREENS += [('genres','Genre picker'),('leanings','Taste leanings'),('providers','Provider links · empty'),('addclub','Add to club · anonymous'),('quickactions','Quick title actions')]
SCREENS += [('franchise','Franchise path'),('why','Why this title · sample explanation')]
def run(args,**kw): return subprocess.run(args,check=True,**kw)
def fingerprint():
 h=hashlib.sha256()
 for base in ['Kuro','Kuro.xcodeproj','Config','Info.plist']:
  p=ROOT/base
  for f in sorted(p.rglob('*') if p.is_dir() else [p]):
   if f.is_file() and 'xcuserdata' not in str(f): h.update(str(f.relative_to(ROOT)).encode());h.update(f.read_bytes())
 return h.hexdigest()
def manifest(data):
 OUT.mkdir(exist_ok=True);p=OUT/'manifest.tmp';p.write_text(json.dumps(data));p.replace(OUT/'manifest.json')
def capture(device):
 version=fingerprint();old=json.loads((OUT/'manifest.json').read_text()) if (OUT/'manifest.json').exists() else {}
 state={**old,'status':'Building current source','pendingVersion':version,'source':str(ROOT)};manifest(state)
 SNAP.mkdir(parents=True,exist_ok=True)
 for name in ['Kuro','Kuro.xcodeproj','Config','KuroTests','KuroUITests']:
  if (ROOT/name).exists():
   shutil.rmtree(SNAP/name,ignore_errors=True);shutil.copytree(ROOT/name,SNAP/name)
 shutil.copy2(ROOT/'Info.plist',SNAP/'Info.plist')
 if fingerprint()!=version: raise RuntimeError('Source changed while copying; waiting for a stable snapshot')
 p=SNAP/'Kuro/KuroApp.swift';s=p.read_text();s=s.replace('init() {', 'init() {\n        UserDefaults.standard.set(true, forKey: "kuro_onboarding_completed")', 1);s=s.replace('RootView(pendingDeepLink: $pendingDeepLink)','CanvasCaptureRoot()');s+='''
private struct CanvasCaptureRoot: View {
 @Environment(SupabaseService.self) private var service
 var route: String { ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--canvas=") })?.components(separatedBy: "=").last ?? "discover" }
 var body: some View {
  Group {
   switch route {
   case "welcome", "signin", "signup", "genie": AuthView()
   case "onboarding", "onboarding1", "onboarding2", "onboarding3", "onboarding4": OnboardingView(onComplete: { _ in })
   case "genres": GenrePickerSheet(genres: ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Thriller"], onSelect: { _ in })
   case "leanings": TasteLeaningsSheet()
   case "providers": ProviderSelectionSheet(title: "Where to watch", links: [], statusCaption: nil, onSelect: { _ in })
   case "import": ConciergeAniListImportSheet(supabaseService: service, isGermanLocale: false, onImportCompleted: { _ in })
   case "club-rails", "club-active", "club-polls": ClubDetailView(clubId: "00000000-0000-0000-0000-000000000000")
   case "club-settings": ClubSettingsSheet(bundle: canvasClub(), clubId: "00000000-0000-0000-0000-000000000000", onDismiss: {})
   case "railitem": AddItemToRailSheet(railId: "00000000-0000-0000-0000-000000000000", clubId: "00000000-0000-0000-0000-000000000000", onAdded: {})
   case "character", "staff", "studio", "author", "credits", "cast": CanvasEntityFrame(route: route)
   case "why", "franchise", "quickactions", "addclub", "verdict", "anime", "manga", "addanime", "addmanga", "episodes", "chapters": CanvasMediaFrame(route: route)
   case "filters": BrowseFiltersSheet(showAnime: true, selectedSort: .popular, selectedStatusFilter: nil, selectedLengthFilter: nil, selectedGenre: nil, selectedDecade: nil, selectedFormat: nil, allGenres: ["Action", "Adventure", "Drama", "Fantasy", "Romance"], onApply: { _ in })
   case "services": StreamingServicePickerSheet()
   case "genre": GenreHubView(genre: "Adventure")
   case "search": NavigationStack { EditorialSearchView() }
   case "profile": ProfileView()
   case "concierge": ConciergeView()
   case "createclub": CreateClubSheet(onCreated: { _ in })
   case "joinclub": JoinClubSheet(onJoined: { _ in })
   case "rail": CreateClubRailSheet(clubId: "00000000-0000-0000-0000-000000000000")
   case "poll": CreateClubPollSheet(clubId: "00000000-0000-0000-0000-000000000000")
   default: ContentView(pendingDeepLink: .constant(nil))
   }
  }
 }
}
private struct CanvasMediaFrame: View {
 let route: String
 @Environment(SupabaseService.self) private var service
 @State private var anime: Anime?
 @State private var manga: Manga?
 @State private var failed = false
 @State private var ladder = MediaLadderResponse.empty
 var body: some View {
  Group {
   if let anime {
    switch route {
    case "franchise": FranchisePathSheet(ladder: ladder)
    case "why": WhyThisSheet(item: .init(mediaType: "ANIME", mediaId: anime.id, matchCount: nil, title: anime.titleEnglish ?? anime.titleRomaji ?? "Title", coverImageMedium: anime.coverImageMedium, averageScore: anime.averageScore, year: anime.seasonYear, format: anime.format, status: anime.status, siteUrl: nil, signals: [], blurb: "Local preview; no personalized recommendation requested."))
    case "quickactions": QuickVerdictActionSheet(media: anime)
    case "addclub": AddToClubRailSheet(mediaId: anime.id, mediaType: "ANIME")
    case "verdict": QuickVerdictPickerSheet(media: anime)
    case "addanime": AddToListSheet(media: anime)
    case "episodes": EpisodeListSheet(anime: anime, episodeCount: anime.episodeCount ?? 0)
    default: AnimeDetailView(anime: anime)
    }
   } else if let manga {
    switch route {
    case "addmanga": AddToListSheet(media: manga)
    case "chapters": ChapterListSheet(manga: manga, chapterCount: manga.chapterCount, chapterStatus: nil)
    default: MangaDetailView(manga: manga)
    }
   } else if failed { Text("Catalog unavailable — capture incomplete") }
   else { ProgressView() }
  }.task {
   do {
    if ["manga", "addmanga", "chapters"].contains(route) { manga = await service.fetchTrendingManga(limit: 1).first; failed = manga == nil }
    else { anime = await service.fetchTrendingAnime(limit: 1).first; failed = anime == nil; if route == "franchise", let anime { ladder = await service.fetchMediaLadder(mediaType: "ANIME", mediaId: anime.id) } }
   } catch { failed = true }
  }
 }
}

private struct CanvasEntityFrame: View {
 let route: String
 @Environment(SupabaseService.self) private var service
 @State private var characters: [(character: Character, role: String)] = []
 @State private var staff: [(staff: Staff, role: String)] = []
 @State private var studios: [Studio] = []
 @State private var authors: [(author: Author, role: String)] = []
 @State private var loaded = false
 var body: some View {
  Group {
   if route == "character", let c = characters.first { CharacterDetailSheet(character: c.character) }
   else if route == "staff", let c = staff.first { StaffDetailSheet(staff: c.staff) }
   else if route == "studio", let c = studios.first { StudioDetailSheet(studio: c) }
   else if route == "author", let c = authors.first { AuthorDetailSheet(author: c.author) }
   else if route == "cast", loaded { CharacterDirectorySheet(title: "Characters", characters: characters) }
   else if route == "credits", loaded { AllCreditsSheet(staffItems: staff) }
   else if loaded { Text("Catalog unavailable — capture incomplete") }
   else { ProgressView() }
  }.task {
   let animeId = await service.fetchTrendingAnime(limit: 1).first?.id ?? -1
   let mangaId = await service.fetchTrendingManga(limit: 1).first?.id ?? -1
   switch route {
   case "character", "cast": characters = await service.fetchCharactersForAnime(animeId: animeId)
   case "staff", "credits": staff = await service.fetchStaffForAnime(animeId: animeId)
   case "studio": studios = await service.fetchStudiosForAnime(animeId: animeId)
   default: authors = await service.fetchAuthorsForManga(mangaId: mangaId)
   }
   loaded = true
  }
 }
}


func canvasClub() -> SupabaseService.ClubBundle {
 let data = #"{"club":{"id":"00000000-0000-0000-0000-000000000000","name":"Preview club","description":"Local sample for visual review","sharing_level":"status","max_members":20,"is_archived":false,"invite_code":"PREVIEW","created_at":"2026-09-30T00:00:00Z"},"members":[],"my_role":"owner","my_sharing_level":"status","rails":[],"polls":[],"member_count":0}"#.data(using: .utf8)!
 return try! JSONDecoder().decode(SupabaseService.ClubBundle.self, from: data)
}

''';p.write_text(s)
 p=SNAP/'Kuro/Views/ClubsView.swift';p.write_text(p.read_text().replace('private struct CreateClubSheet','struct CreateClubSheet').replace('private struct JoinClubSheet','struct JoinClubSheet'))
 p=SNAP/'Kuro/Views/ClubDetailView.swift';p.write_text(p.read_text().replace('private func loadBundle(force: Bool = false) async {', 'private func loadBundle(force: Bool = false) async {\n        bundle = canvasClub(); loadPhase = .loaded; return\n').replace('@State private var selectedTab: Tab = .rails', '@State private var selectedTab: Tab = ProcessInfo.processInfo.arguments.contains("--canvas=club-active") ? .active : (ProcessInfo.processInfo.arguments.contains("--canvas=club-polls") ? .polls : .rails)'))
 p=SNAP/'Kuro/Views/DetailPages/AdaptationPathSection.swift';p.write_text(p.read_text().replace('private struct FranchisePathSheet','struct FranchisePathSheet'))
 p=SNAP/'Kuro/Views/DetailPages/CastSection.swift';p.write_text(p.read_text().replace('private struct CharacterDirectorySheet','struct CharacterDirectorySheet'))
 for view in ['BrowseView', 'TastePicksView']:
  p=SNAP/('Kuro/Views/'+view+'.swift')
  if not p.exists(): continue
  p.write_text(p.read_text().replace('@State private var showAnime = true', '@State private var showAnime = !ProcessInfo.processInfo.arguments.contains("--canvas-manga")'))
 p=SNAP/'Kuro/Views/OnboardingView.swift';p.write_text(p.read_text().replace('@State private var currentPage = 0', '@State private var currentPage = Int(ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--canvas-page=") })?.components(separatedBy: "=").last ?? "0") ?? 0'))
 p=SNAP/'Kuro/Views/ProfileView.swift';p.write_text(p.read_text().replace('private struct StreamingServicePickerSheet','struct StreamingServicePickerSheet'))
 p=SNAP/'Kuro/Views/AuthView.swift';p.write_text(p.read_text().replace('@State private var mode: Mode = .signIn','@State private var mode: Mode = ProcessInfo.processInfo.arguments.contains("--canvas=signup") ? .signUp : .signIn'))
 with (OUT/'build.log').open('w') as log:
  run(['xcodebuild','-project',str(SNAP/'Kuro.xcodeproj'),'-scheme','Kuro','-configuration','Debug','-destination',f'platform=iOS Simulator,id={device}','-derivedDataPath',str(OUT/'build'),'build','CODE_SIGNING_ALLOWED=NO',f'PRODUCT_BUNDLE_IDENTIFIER={BUNDLE}','INFOPLIST_KEY_CFBundleDisplayName=Kuro Canvas'],stdout=log,stderr=subprocess.STDOUT)
 run(['xcrun','simctl','install',device,str(OUT/'build/Build/Products/Debug-iphonesimulator/Kuro.app')])
 generation=OUT/(version[:12]+'-'+str(int(time.time())));generation.mkdir(exist_ok=True);frames=list(old.get('frames',[])) if old.get('version')==version else []
 for key,title in SCREENS:
  if any(f['id']==key for f in frames): continue
  state['status']='Capturing '+title;manifest(state)
  args=['xcrun','simctl','launch','--terminate-running-process',device,BUNDLE,'--kuro-skip-auth',f'--canvas={key}',f'--kuro-start={key.split("-")[0]}']
  if key.endswith('-manga'): args.append('--canvas-manga')
  if key.startswith('onboarding') and key != 'onboarding': args.append('--canvas-page='+key[-1])
  if key == 'genie': args.append('-AuthGenieHero')
  if key in ['signin','signup']: args.append('-AuthShowEmail')
  run(args,stdout=subprocess.DEVNULL);time.sleep(5)
  run(['xcrun','simctl','io',device,'screenshot',str(generation/(key+'.png'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  frames.append({'id':key,'title':title,'image':generation.name+'/'+key+'.png','note':'Actual SwiftUI · local sample club' if key.startswith('club-') else 'Actual SwiftUI · isolated anonymous preview'})
 manifest({'source':str(ROOT),'version':version,'generation':generation.name,'capturedAt':time.strftime('%Y-%m-%d %H:%M:%S'),'status':'Ready' if fingerprint()==version else 'Source changed; rebuilding','frames':frames,'limitations':'Initial viewports only. Club detail uses an empty local sample. Populated collections, deeper scroll positions, dialogs and account-specific states are not captured. Anonymous previews do not prove account behavior.'})
 return version
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--device',required=True);p.add_argument('--watch',action='store_true');a=p.parse_args();last=None
 while True:
  current=fingerprint()
  if current!=last:
   try:last=capture(a.device)
   except Exception as e:
    old=json.loads((OUT/'manifest.json').read_text()) if (OUT/'manifest.json').exists() else {};manifest({**old,'status':'Capture failed; previous images are stale','error':str(e)});last=current
  if not a.watch:break
  time.sleep(3)
