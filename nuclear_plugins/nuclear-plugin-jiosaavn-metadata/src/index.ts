import type {
  Album,
  AlbumRef,
  ArtistBio,
  ArtistRef,
  ArtworkSet,
  MetadataProvider,
  NuclearPlugin,
  NuclearPluginAPI,
  PlaylistRef,
  SearchParams,
  SearchResults,
  Track,
  TrackRef,
} from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-metadata';
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

const artistPairs = (rawNames: string | undefined, rawIds: string | undefined): { name: string; id: string }[] => {
  const names = artistNames(rawNames);
  const ids = (rawIds ?? '').split(',').map((n) => n.trim()).filter(Boolean);
  return names.map((name, index) => ({ name, id: ids[index] ?? name }));
};

const artistCredits = (song: any) =>
  artistPairs(song.primary_artists ?? song.singers ?? 'Unknown Artist', song.primary_artists_id).map(({ name, id }) => ({ name, roles: [], source: { provider: PROVIDER_ID, id } }));

const artistRefs = (song: any): ArtistRef[] =>
  artistPairs(song.primary_artists ?? song.singers ?? 'Unknown Artist', song.primary_artists_id).map(({ name, id }) => ({
    name,
    source: { provider: PROVIDER_ID, id },
  }));

const toTrack = (song: any): Track => ({
  title: song.song ?? song.title ?? 'Unknown',
  artists: artistCredits(song),
  album: song.album
    ? { title: song.album, artists: artistRefs(song), source: { provider: PROVIDER_ID, id: String(song.albumid ?? '') } }
    : undefined,
  durationMs: parseInt(song.duration ?? '0', 10) * 1000 || undefined,
  artwork: artwork(song.image, 'thumbnail'),
  source: { provider: PROVIDER_ID, id: String(song.id), url: song.perma_url },
});

const toTrackRef = (song: any): TrackRef => ({
  title: song.song ?? song.title ?? 'Unknown',
  artists: artistRefs(song),
  artwork: artwork(song.image, 'thumbnail'),
  source: { provider: PROVIDER_ID, id: String(song.id), url: song.perma_url },
});

const toAlbumRef = (album: any): AlbumRef => ({
  title: album.title ?? album.name ?? 'Unknown',
  artists: artistPairs(album.primary_artists ?? album.artists?.[0]?.name, album.primary_artists_id).map(({ name, id }) => ({
    name,
    source: { provider: PROVIDER_ID, id },
  })),
  artwork: artwork(album.image),
  source: { provider: PROVIDER_ID, id: String(album.albumid ?? album.id ?? ''), url: album.perma_url },
});

const toArtistRef = (artist: any): ArtistRef => ({
  name: artist.name ?? 'Unknown',
  disambiguation: artist.subtitle ?? undefined,
  artwork: artwork(artist.image, 'avatar'),
  source: { provider: PROVIDER_ID, id: String(artist.id ?? '') },
});

const toPlaylistRef = (playlist: any): PlaylistRef => ({
  id: String(playlist.listid ?? playlist.id ?? ''),
  name: playlist.listname ?? playlist.title ?? 'Unknown',
  artwork: artwork(playlist.image),
  source: { provider: PROVIDER_ID, id: String(playlist.listid ?? playlist.id ?? ''), url: playlist.perma_url },
});

const createProvider = (api: NuclearPluginAPI): MetadataProvider => ({
  id: PROVIDER_ID,
  kind: 'metadata',
  name: 'JioSaavn',
  streamingProviderId: 'jiosaavn-streaming',
  searchCapabilities: ['artists', 'albums', 'tracks', 'playlists'],
  artistMetadataCapabilities: ['artistBio', 'artistAlbums', 'artistTopTracks'],
  albumMetadataCapabilities: ['albumDetails'],

  search: async ({ query, limit }: SearchParams): Promise<SearchResults> => {
    const n = String(limit ?? 10);
    const [tracks, albums, artists, playlists] = await Promise.allSettled([
      callApi(api, { __call: 'search.getResults', q: query, n }),
      callApi(api, { __call: 'search.getAlbumResults', q: query, n }),
      callApi(api, { __call: 'search.getArtistResults', q: query, n }),
      callApi(api, { __call: 'search.getPlaylistResults', q: query, n }),
    ]);
    return {
      tracks: tracks.status === 'fulfilled' ? (tracks.value.results ?? []).map(toTrack) : [],
      albums: albums.status === 'fulfilled' ? (albums.value.results ?? []).map(toAlbumRef) : [],
      artists: artists.status === 'fulfilled' ? (artists.value.results ?? []).map(toArtistRef) : [],
      playlists: playlists.status === 'fulfilled' ? (playlists.value.results ?? []).map(toPlaylistRef) : [],
    };
  },

  searchArtists: async ({ query, limit }) => {
    const data = await callApi(api, { __call: 'search.getArtistResults', q: query, n: String(limit ?? 10) });
    return (data.results ?? []).map(toArtistRef);
  },

  searchAlbums: async ({ query, limit }) => {
    const data = await callApi(api, { __call: 'search.getAlbumResults', q: query, n: String(limit ?? 10) });
    return (data.results ?? []).map(toAlbumRef);
  },

  searchTracks: async ({ query, limit }) => {
    const data = await callApi(api, { __call: 'search.getResults', q: query, n: String(limit ?? 10) });
    return (data.results ?? []).map(toTrack);
  },

  searchPlaylists: async ({ query, limit }) => {
    const data = await callApi(api, { __call: 'search.getPlaylistResults', q: query, n: String(limit ?? 10) });
    return (data.results ?? []).map(toPlaylistRef);
  },

  fetchAlbumDetails: async (query) => {
    const data = await callApi(api, { __call: 'content.getAlbumDetails', albumid: query });
    return {
      title: data.title ?? 'Unknown',
      artists: artistCredits(data),
      tracks: (data.songs ?? []).map(toTrackRef),
      artwork: artwork(data.image),
      source: { provider: PROVIDER_ID, id: String(data.albumid ?? query) },
    } as Album;
  },

  fetchArtistBio: async (artistId) => {
    try {
      const data = await callApi(api, { __call: 'artist.getArtistPageDetails', artistId });
      return {
        name: data.name ?? 'Unknown',
        disambiguation: data.subtitle ?? undefined,
        bio: data.bio ?? undefined,
        onTour: Boolean(data.is_on_tour),
        artwork: artwork(data.image, 'avatar'),
        source: { provider: PROVIDER_ID, id: artistId },
      } as ArtistBio;
    } catch {
      return {
        name: 'Unknown',
        source: { provider: PROVIDER_ID, id: artistId },
      };
    }
  },

  fetchArtistAlbums: async (artistId) => {
    try {
      const data = await callApi(api, { __call: 'artist.getArtistPageDetails', artistId });
      return (data.topAlbums ?? []).map(toAlbumRef);
    } catch {
      return [];
    }
  },

  fetchArtistTopTracks: async (artistId) => {
    try {
      const data = await callApi(api, { __call: 'artist.getArtistPageDetails', artistId });
      return (data.topSongs ?? []).map(toTrackRef);
    } catch {
      return [];
    }
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
