# Configuration

## YouTube API Key

The app no longer embeds the YouTube Data API key in source control. Supply the key in one of the following ways before running features that rely on the YouTube API:

1. **Secrets plist (recommended for local development)**
   1. Copy `ThumbnailMaker/Config/Secrets.example.plist` to `ThumbnailMaker/Config/Secrets.plist`.
   2. Replace the placeholder value for `YOUTUBE_API_KEY` with your actual key.
   3. Ensure `Secrets.plist` remains untracked—it's ignored by `.gitignore`.

2. **Environment variable (useful for CI)**
   * Set the `YOUTUBE_API_KEY` environment variable before launching the app or running UI tests.

At runtime the app first checks the environment variable, then looks for `Secrets.plist`. If neither source is present an assertion failure is raised and requests to the YouTube API will use an empty key.
