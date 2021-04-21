# Artifactory Migrator

## Introduction

Sometimes we want to migrate our registries to another service. This tool can
help you to migrate packages from one registry to another.

Currently, we only support migrate ruby gems and npm packages.

## Setup

1. Copy `config.yml.example` to `config.yml`
2. Fill registry information
3. Patch `gem` and `npm` command
   > ruby gem or npm package might set allowed registry host name. By default,
   > `gem` / `npm` will prevent you to publish it to another registry. So we have
   > to patch it to make it work. And you can revert it back later.
   4. gem
      
      Edit `commands/push_command.rb` under your ruby installed `site_ruby` dir.
      Comment this line: `push_host = gem_data.spec.metadata['allowed_push_host']`
      to make sure gem push won't check `allowed_push_host`.
      
   2. npm

     Edit `lib/unpublish.js` under your npm dir.

     Change
     `return libunpub(npa.resolve(data.name, data.version), opts.concat(data.publishConfig))`

     To

     `return libunpub(npa.resolve(data.name, data.version), opts.concat({}))`



## Migrate

`ruby migrate.rb`