import type {
  AlbumRef,
  ArtworkSet,
  DashboardProvider,
  NuclearPlugin,
  NuclearPluginAPI,
  Playlist,
  PlaylistProvider,
  PlaylistRef,
  Track,
} from '@nuclearplayer/plugin-sdk';

const DASHBOARD_PROVIDER_ID = 'jiosaavn-dashboard';
const PLAYLISTS_PROVIDER_ID = 'jiosaavn-playlists';
const API_BASE = 'https://www.jiosaavn.com/api.php';
const PREFERRED_LANGUAGES = ['malayalam', 'tamil', 'hindi', 'english', 'telugu'];
const CACHE_TTL_MS = 10 * 60 * 1000;

const callApi = async (
  api: NuclearPluginAPI,
  params: Record<string, string>,
): Promise<any> => {
  const query = new URLSearchParams({
    __call: params.__call,
    _format: 'json',
    _marker: '0',
    ctx: 'web6dot0',
    cc: 'in',
    ...params,
  });
  const res = await api.Http.fetch(`${API_BASE}?${query}`, {
    headers: { 'User-Agent': 'Mozilla/5.0' },
  });
  if (!res.ok) {
    throw new Error(`JioSaavn API error ${res.status}`);
  }
  return res.json();
};

const artwork = (url: string | undefined, purpose: 'cover' | 'thumbnail' | 'avatar' = 'cover'): ArtworkSet | undefined =>
  url ? { items: [{ url, purpose }] } : undefined;

const artistNames = (raw: string | undefined): string[] =>
  (raw ?? '').split(/,| featuring /i).map((n) => n.trim()).filter(Boolean);

const languageRank = (lang: string | undefined): number => {
  if (!lang) {
    return PREFERRED_LANGUAGES.length;
  }
  const idx = PREFERRED_LANGUAGES.indexOf(lang.toLowerCase());
  return idx === -1 ? PREFERRED_LANGUAGES.length : idx;
};

const byLanguagePreference = <T extends { language?: string }>(a: T, b: T): number =>
  languageRank(a.language) - languageRank(b.language);

const artistPairs = (rawNames: string | undefined, rawIds: string | undefined): { name: string; id: string }[] => {
  const names = artistNames(rawNames);
  const ids = (rawIds ?? '').split(',').map((n) => n.trim()).filter(Boolean);
  return names.map((name, index) => ({ name, id: ids[index] ?? name }));
};

const toAlbumRef = (album: any): AlbumRef => ({
  title: album.title ?? 'Unknown',
  artists: artistPairs(album.primary_artists ?? album.artists?.[0]?.name, album.primary_artists_id).map(({ name, id }) => ({
    name,
    source: { provider: DASHBOARD_PROVIDER_ID, id },
  })),
  artwork: artwork(album.image),
  source: { provider: DASHBOARD_PROVIDER_ID, id: String(album.albumid ?? album.id ?? ''), url: album.perma_url },
});

const toPlaylistRef = (playlist: any): PlaylistRef => ({
  id: String(playlist.listid ?? playlist.id ?? ''),
  name: playlist.listname ?? playlist.title ?? 'Unknown',
  artwork: artwork(playlist.image),
  source: { provider: DASHBOARD_PROVIDER_ID, id: String(playlist.listid ?? playlist.id ?? ''), url: playlist.perma_url },
});

const toTrack = (song: any): Track => ({
  title: song.song ?? song.title ?? 'Unknown',
  artists: artistPairs(song.primary_artists ?? song.singers ?? 'Unknown Artist', song.primary_artists_id).map(({ name, id }) => ({ name, roles: [], source: { provider: DASHBOARD_PROVIDER_ID, id } })),
  durationMs: parseInt(song.duration ?? '0', 10) * 1000 || undefined,
  artwork: artwork(song.image, 'thumbnail'),
  source: { provider: DASHBOARD_PROVIDER_ID, id: String(song.id), url: song.perma_url },
});

type LanguageData = {
  language: string;
  playlist: any;
  tracks: any[];
  albums: any[];
};

const createDashboardProvider = (api: NuclearPluginAPI): DashboardProvider => {
  let trendingCache: { fetchedAt: number; items: any[] } | undefined;
  let languageCache: { fetchedAt: number; data: LanguageData[] } | undefined;

  const getTrending = async (): Promise<any[]> => {
    const now = Date.now();
    if (trendingCache && now - trendingCache.fetchedAt < CACHE_TTL_MS) {
      return trendingCache.items;
    }
    const data = await callApi(api, { __call: 'content.getTrending', n: '60' });
    trendingCache = { fetchedAt: now, items: data ?? [] };
    return trendingCache.items;
  };

  const getLanguageData = async (): Promise<LanguageData[]> => {
    const now = Date.now();
    if (languageCache && now - languageCache.fetchedAt < CACHE_TTL_MS) {
      return languageCache.data;
    }

    const isDecadePlaylist = (name: string): boolean => /(?:19|20)\d0s/i.test(name);

    const playlists = await Promise.all(
      PREFERRED_LANGUAGES.map(async (language) => {
        const data = await callApi(api, { __call: 'search.getPlaylistResults', q: `${language} top 50`, n: '6' });
        const candidates = (data.results ?? []).filter((pl: any) => (pl.language ?? '').toLowerCase() === language);
        return candidates.find((pl: any) => !isDecadePlaylist(pl.listname ?? '')) ?? candidates[0];
      }),
    );

    const albums = await Promise.all(
      PREFERRED_LANGUAGES.map(async (language) => {
        const data = await callApi(api, { __call: 'search.getAlbumResults', q: `${language} songs`, n: '5' });
        return (data.results ?? []).filter((al: any) => (al.language ?? '').toLowerCase() === language);
      }),
    );

    const tracksPerLanguage = await Promise.all(
      playlists.map(async (playlist) => {
        if (!playlist) {
          return [];
        }
        try {
          const data = await callApi(api, {
            __call: 'playlist.getDetails',
            listid: String(playlist.listid),
            n: '20',
          });
          return (data.songs ?? []).filter(
            (song: any) => !song.language || (song.language ?? '').toLowerCase() === (playlist.language ?? '').toLowerCase(),
          );
        } catch {
          return [];
        }
      }),
    );

    const data = PREFERRED_LANGUAGES.map((language, index) => ({
      language,
      playlist: playlists[index],
      tracks: tracksPerLanguage[index],
      albums: albums[index],
    }));
    languageCache = { fetchedAt: now, data };
    return data;
  };

  return {
    id: DASHBOARD_PROVIDER_ID,
    kind: 'dashboard',
    name: 'JioSaavn',
    metadataProviderId: 'jiosaavn-metadata',
    capabilities: [
      'topTracks',
      'topAlbums',
      'editorialPlaylists',
      'newReleases',
    ],

    async fetchTopTracks() {
      const languageData = await getLanguageData();
      const seen = new Set<string>();
      const songs = languageData
        .flatMap((entry) => entry.tracks)
        .filter((song: any) => {
          const id = String(song.id);
          if (seen.has(id)) {
            return false;
          }
          seen.add(id);
          return true;
        })
        .sort(byLanguagePreference)
        .slice(0, 30);
      return songs.map(toTrack);
    },

    async fetchTopAlbums() {
      const languageData = await getLanguageData();
      const trending = await getTrending();
      const seen = new Set<string>();
      return [...languageData.flatMap((entry) => entry.albums), ...trending.filter((item: any) => item.type === 'album').map((item: any) => item.details)]
        .filter((album: any) => {
          const id = String(album.albumid ?? album.id);
          if (seen.has(id)) {
            return false;
          }
          seen.add(id);
          return true;
        })
        .sort(byLanguagePreference)
        .map(toAlbumRef);
    },

    async fetchEditorialPlaylists() {
      const languageData = await getLanguageData();
      const trending = await getTrending();
      const seen = new Set<string>();
      return [...languageData.map((entry) => entry.playlist).filter(Boolean), ...trending.filter((item: any) => item.type === 'playlist').map((item: any) => item.details)]
        .filter((playlist: any) => {
          const id = String(playlist.listid);
          if (seen.has(id)) {
            return false;
          }
          seen.add(id);
          return true;
        })
        .map(toPlaylistRef);
    },

    async fetchNewReleases() {
      const trending = await getTrending();
      return trending
        .filter((item: any) => item.type === 'album')
        .map((item: any) => item.details)
        .sort(byLanguagePreference)
        .map(toAlbumRef);
    },
  };
};

const createPlaylistsProvider = (api: NuclearPluginAPI): PlaylistProvider => ({
  id: PLAYLISTS_PROVIDER_ID,
  kind: 'playlists',
  name: 'JioSaavn',

  matchesUrl: (url: string) => /jiosaavn\.com\//i.test(url),

  fetchPlaylistByUrl: async (url) => {
    const token = url.split('/').filter(Boolean).pop() ?? '';
    const data = await callApi(api, { __call: 'webapi.get', type: 'playlist', token });
    const songs = data?.songs ?? [];
    const now = new Date().toISOString();
    const playlist: Playlist = {
      id: String(data?.listid ?? token),
      name: data?.listname ?? 'JioSaavn Playlist',
      artwork: artwork(data?.image),
      createdAtIso: now,
      lastModifiedIso: now,
      origin: { provider: PLAYLISTS_PROVIDER_ID, id: String(data?.listid ?? token), url },
      isReadOnly: true,
      items: songs.map((song: any, index: number) => ({
        id: `${song.id}-${index}`,
        track: toTrack(song),
        addedAtIso: now,
      })),
    };
    return playlist;
  },
});

const plugin: NuclearPlugin = {
  onEnable(api: NuclearPluginAPI) {
    api.Providers.register(createDashboardProvider(api));
    api.Providers.register(createPlaylistsProvider(api));
  },

  onDisable(api: NuclearPluginAPI) {
    api.Providers.unregister(DASHBOARD_PROVIDER_ID);
    api.Providers.unregister(PLAYLISTS_PROVIDER_ID);
  },
};

export default plugin;
