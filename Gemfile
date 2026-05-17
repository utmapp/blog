source "https://rubygems.org"

# Plain Jekyll (not the `github-pages` gem) so local builds run the
# Ruby plugin in `_plugins/authorship.rb`. The github-pages gem forces
# Jekyll into `safe` mode, which disables user plugins.
#
# Production builds go through .github/workflows/pages.yml, which also
# uses plain Jekyll and ships the rendered _site/ via actions/deploy-pages.
gem "jekyll", "~> 4.3"

group :jekyll_plugins do
  gem "jekyll-feed",    "~> 0.17"
  gem "jekyll-seo-tag", "~> 2.8"
  gem "jekyll-sitemap", "~> 1.4"
end

# Windows / JRuby zoneinfo + watcher.
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
  gem "wdm", "~> 0.1.1"
end

gem "http_parser.rb", "~> 0.6.0", platforms: [:jruby]
