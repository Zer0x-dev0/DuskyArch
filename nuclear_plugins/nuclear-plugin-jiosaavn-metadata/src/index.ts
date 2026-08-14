import type { MetadataProvider, NuclearPlugin } from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-metadata';

const createProvider = (): MetadataProvider => ({
  id: PROVIDER_ID,
  kind: 'metadata',
  name: 'JioSaavn',
  description: 'JioSaavn metadata provider for Nuclear',
  streamingProviderId: 'jiosaavn-streaming',
  searchCapabilities: ['artists', 'albums', 'tracks', 'playlists'],
  artistMetadataCapabilities: ['artistBio', 'artistAlbums', 'artistTopTracks'],
  albumMetadataCapabilities: ['albumDetails'],
  search: async () => ({}),
  searchArtists: async ({ query, limit }) => [],
  searchAlbums: async ({ query, limit }) => [],
  searchTracks: async ({ query, limit }) => [],
  searchPlaylists: async ({ query, limit }) => [],
  fetchArtistBio: async (id) => '',
  fetchArtistAlbums: async (id) => [],
  fetchArtistTopTracks: async (id) => [],
  fetchAlbumDetails: async (id) => undefined,
});

const plugin: NuclearPlugin = {
  onEnable(api) {
    api.Providers.register(createProvider());
  },
  onDisable(api) {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;