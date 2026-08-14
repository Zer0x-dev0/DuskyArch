import type {
  AlbumRef,
  ArtworkSet,
  DashboardProvider,
  NuclearPlugin,
  NuclearPluginAPI,
  PlaylistRef,
  Track,
} from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-dashboard';
const API_BASE = 'https://www.jiosaavn.com/api.php';

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

const toAlbumRef = (album: any): AlbumRef => ({
  title: album.title ?? 'Unknown',
  artists: artistNames(album.primary_artists ?? album.artists?.[0]?.name).map((name) => ({
    name,
    source: { provider: PROVIDER_ID, id: name },
  })),
  artwork: artwork(album.image),
  source: { provider: PROVIDER_ID, id: String(album.albumid ?? album.id ?? ''), url: album.perma_url },
});

const toPlaylistRef = (playlist: any): PlaylistRef => ({
  id: String(playlist.listid ?? playlist.id ?? ''),
  name: playlist.listname ?? playlist.title ?? 'Unknown',
  artwork: artwork(playlist.image),
  source: { provider: PROVIDER_ID, id: String(playlist.listid ?? playlist.id ?? ''), url: playlist.perma_url },
});

const toTrack = (song: any): Track => ({
  title: song.song ?? song.title ?? 'Unknown',
  artists: artistNames(song.primary_artists ?? song.singers ?? 'Unknown Artist').map((name) => ({ name, roles: [] })),
  durationMs: parseInt(song.duration ?? '0', 10) * 1000 || undefined,
  artwork: artwork(song.image, 'thumbnail'),
  source: { provider: PROVIDER_ID, id: String(song.id), url: song.perma_url },
});

const createProvider = (api: NuclearPluginAPI): DashboardProvider => ({
  id: PROVIDER_ID,
  kind: 'dashboard',
  name: 'JioSaavn',
  capabilities: [
    'topTracks',
    'topAlbums',
    'editorialPlaylists',
    'newReleases',
  ],

  async fetchTopTracks() {
    const data = await callApi(api, { __call: 'content.getTrending', lang: 'hindi', n: '40' });
    return (data ?? []).filter((item: any) => item.type === 'song').map((item: any) => toTrack(item.details));
  },

  async fetchTopAlbums() {
    const data = await callApi(api, { __call: 'content.getTrending', lang: 'hindi', n: '40' });
    return (data ?? []).filter((item: any) => item.type === 'album').map((item: any) => toAlbumRef(item.details));
  },

  async fetchEditorialPlaylists() {
    const data = await callApi(api, { __call: 'content.getTrending', lang: 'hindi', n: '40' });
    return (data ?? []).filter((item: any) => item.type === 'playlist').map((item: any) => toPlaylistRef(item.details));
  },

  async fetchNewReleases() {
    const data = await callApi(api, { __call: 'content.getTrending', lang: 'hindi', n: '40' });
    return (data ?? []).filter((item: any) => item.type === 'album').map((item: any) => toAlbumRef(item.details));
  },
});

const plugin: NuclearPlugin = {
  onEnable(api: NuclearPluginAPI) {
    api.Providers.register(createProvider(api));
  },

  onDisable(api: NuclearPluginAPI) {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;
