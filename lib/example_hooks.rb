# frozen_string_literal: true

# EXAMPLE FILE — This gem is a real rubygems plugin, but this file is not that.
#                This file is NOT a real RubyGems plugin.
#
# This file is a toy/reference showing the RubyGems hook APIs available to
# plugins.  It is NOT automatically loaded by RubyGems and does nothing on
# its own.  The real plugin entry point for this gem is rubygems_plugin.rb.
#
# For context, RubyGems discovers plugins via two paths:
#
# 1. AT STARTUP: Gem.load_plugins / Gem.load_env_plugins (called by GemRunner#run
#    before any command executes) -- loads plugins from already-installed gems.
#
# 2. HOT-LOAD DURING INSTALL: Gem::Installer#load_plugin (called at the end of
#    each gem's install step) -- hot-loads a plugin into the running process
#    the moment its gem is installed for the first time.
#
# The hot-load path matters because RubyGems installs dependencies in
# topological order (leaves first, via RequestSet#sorted_requests which uses
# TSort), so a gem that carries a rubygems_plugin.rb will have that plugin
# live-loaded *before* any gem that depends on it finishes installing.  That
# means hooks registered by the plugin are active for every gem installed
# afterward in the same `gem install` invocation.
#
# IMPORTANT CAVEAT (from Gem::Installer#load_plugin source):
#   return unless Gem::Specification.find_all_by_name(spec.name).size == 1
# The hot-load only fires when this is the *first* version of the gem on the
# system.  If any prior version is already installed the plugin stub is
# regenerated in $GEM_HOME/plugins/ but the file is NOT required into the
# running process to avoid loading two versions simultaneously.
#
# The hooks below are documented as a reference for potential future use.

# ---------------------------------------------------------------------------
# Gem.pre_install  -- runs before each gem's files are extracted
# ---------------------------------------------------------------------------
# Return false from the block to abort the installation with Gem::InstallError.
Gem.pre_install do |installer|
  # installer is a Gem::Installer instance; installer.spec is the gemspec.
  # Returning nil / any truthy value lets the install proceed.
end

# ---------------------------------------------------------------------------
# Gem.post_build  -- runs after native extensions are compiled but before
#                    bin stubs and the spec file are written
# ---------------------------------------------------------------------------
# Return false from the block to abort the installation and remove gem_dir.
Gem.post_build do |installer|
end

# ---------------------------------------------------------------------------
# Gem.post_install  -- runs after the gem is fully installed
# ---------------------------------------------------------------------------
Gem.post_install do |installer|
end

# ---------------------------------------------------------------------------
# Gem.done_installing  -- runs once after ALL gems in a batch are installed
#                         (registered on DependencyInstaller, not Installer)
# ---------------------------------------------------------------------------
# `installer`  -- the Gem::DependencyInstaller that orchestrated the run
# `specs`      -- Array of Gem::Specification for every gem installed
Gem.done_installing do |installer, specs|
end
