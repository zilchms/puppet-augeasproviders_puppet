# frozen_string_literal: true

# Alternative Augeas-based providers for Puppet
#
# Copyright (c) 2012 Raphaël Pinson
# Licensed under the Apache License, Version 2.0

raise('Missing augeasproviders_core dependency') if Puppet::Type.type(:augeasprovider).nil?

Puppet::Type.type(:puppet_auth).provide(:augeas, parent: Puppet::Type.type(:augeasprovider).provider(:default)) do
  desc "Uses Augeas API to update a rule in Puppet's auth.conf."

  INS_ALIASES = {
    'first allow' => 'path[allow][1]',
    'last allow'  => 'path[allow][last()]',
    'first deny'  => 'path[count(allow)=0][1]',
    'last deny'   => 'path[count(allow)=0][last()]',
  }.freeze

  default_file { File.join(Puppet[:confdir], 'auth.conf') }

  lens { 'Puppet_Auth.lns' }

  confine feature: :augeas

  resource_path do |resource|
    path = resource[:path]
    "$target/path[.='#{path}']"
  end

  def self.instances
    resources = []
    augopen do |aug|
      settings = aug.match('$target/path')

      settings.each do |node|
        # Set $resource for getters
        aug.defvar('resource', node)

        path = aug.get(node)
        path_regex = aug.match("#{node}/operator[.='~']").empty? ? :false : :true
        environments = attr_aug_reader_environments(aug)
        methods = attr_aug_reader_methods(aug)
        allow = attr_aug_reader_allow(aug)
        allow_ip = attr_aug_reader_allow_ip(aug)
        authenticated = attr_aug_reader_authenticated(aug)
        name = path_regex == :false ? "Auth rule for #{path}" : "Auth rule matching #{path}"
        entry = { ensure: :present, name: name,
                  path: path, path_regex: path_regex,
                  environments: environments, methods: methods,
                  allow: allow, allow_ip: allow_ip,
                  authenticated: authenticated }
        resources << new(entry) if entry[:path]
      end
    end
    resources
  end

  def create
    apath = resource[:path]
    apath_regex = resource[:path_regex]
    before = resource[:ins_before]
    after = resource[:ins_after]
    environments = resource[:environments]
    methods = resource[:methods]
    allow = resource[:allow]
    allow_ip = resource[:allow_ip]
    authenticated = resource[:authenticated]
    augopen! do |aug|
      if before || after
        expr = before || after
        expr = INS_ALIASES[expr] if INS_ALIASES.key?(expr)
        aug.insert("$target/#{expr}", 'path', before ? true : false)
        aug.set("$target/path[.='']", apath)
      end

      aug.set(resource_path, apath)
      # Refresh $resource
      setvars(aug)
      aug.set('$resource/operator', '~') if apath_regex == :true
      attr_aug_writer_environments(aug, environments)
      attr_aug_writer_methods(aug, methods)
      attr_aug_writer_allow(aug, allow)
      attr_aug_writer_allow_ip(aug, allow_ip)
      attr_aug_writer_authenticated(aug, authenticated)
    end
  end

  attr_aug_accessor(:environments,
                    label: 'environment',
                    type: :array,
                    sublabel: :seq,
                    purge_ident: true)

  attr_aug_accessor(:methods,
                    label: 'method',
                    type: :array,
                    sublabel: :seq,
                    purge_ident: true)

  attr_aug_accessor(:allow,
                    type: :array,
                    sublabel: :seq,
                    purge_ident: true)

  attr_aug_accessor(:allow_ip,
                    type: :array,
                    sublabel: :seq,
                    purge_ident: true)

  attr_aug_accessor(:authenticated,
                    label: 'auth',
                    purge_ident: true)
end
