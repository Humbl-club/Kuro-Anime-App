// Fictional accounts for design review. No real account, analytics or network writes.
const HOME_FIXTURES = {
  returning: {
    label: 'Returning member', lastVisit: 'Yesterday', mangaLanguage: 'English',
    library: {
      anime: [
        { id: 1, status: 'Watching', progress: 3, lastUsed: 'Yesterday' },
        { id: 0, status: 'Watching', progress: 7, lastUsed: 'Last week' },
        { id: 2, status: 'Planned', progress: 0, saved: 'Last week' },
        { id: 3, status: 'Finished', progress: 37 }
      ],
      manga: [
        { id: 0, status: 'Reading', progress: 24, lastUsed: 'Yesterday' },
        { id: 1, status: 'Reading', progress: 8, lastUsed: 'Last week' },
        { id: 2, status: 'Planned', progress: 0, saved: 'Last week' },
        { id: 3, status: 'Paused', progress: 12, lastUsed: 'Three weeks ago' }
      ]
    },
    follows: { anime: [1, 2], manga: [1, 2] },
    clubs: [{ name: 'Sunday Club', media: { anime: [2, 3], manga: [2, 3] }, notes: { anime: 3, manga: 3 } }]
  },
  new: {
    label: 'New member', lastVisit: null, mangaLanguage: 'English',
    library: { anime: [], manga: [] }, follows: { anime: [], manga: [] }, clubs: []
  }
};
// Availability and release events are also illustrative; they are not provider facts.
const HOME_EVENTS = {
  anime: {
    available: { 0: 8, 1: 4, 2: 24, 3: 37 },
    newEpisodes: { 0: 8, 1: 4 },
    releases: [
      { id: 1, when: 'Tomorrow', detail: '18:00', label: 'Episode 5', kind: 'episode' },
      { id: 2, when: 'Announced', detail: '', label: 'New season', kind: 'season' }
    ]
  },
  manga: {
    releases: [
      { id: 1, when: 'October', language: 'English', label: 'Next volume' },
      { id: 2, when: 'Announced', language: 'English', label: 'New edition' }
    ]
  }
};
