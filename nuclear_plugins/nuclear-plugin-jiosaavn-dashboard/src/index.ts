import type { DashboardProvider, NuclearPlugin } from '@nuclearplayer/plugin-sdk';

const PROVIDER_ID = 'jiosaavn-dashboard';

const createProvider = (): DashboardProvider => ({
  id: PROVIDER_ID,
  name: 'JioSaavn',
  description: 'JioSaavn dashboard provider for Nuclear',
  capabilities: ['topTracks', 'topArtists', 'topAlbums', 'editorialPlaylists', 'newReleases'],
  fetchTopTracks: async () => [],
  fetchTopArtists: async () => [],
  fetchTopAlbums: async () => [],
  fetchEditorialPlaylists: async () => [],
  fetchNewReleases: async () => [],
});

const plugin: NuclearPlugin = {
  onEnable: (api) => {
    api.Providers.register(createProvider());
  },
  onDisable: (api) => {
    api.Providers.unregister(PROVIDER_ID);
  },
};

export default plugin;
