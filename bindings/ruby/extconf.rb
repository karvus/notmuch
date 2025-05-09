#!/usr/bin/env ruby
# coding: utf-8
# Copyright 2010, 2011, 2012 Ali Polatel <alip@exherbo.org>
# Distributed under the terms of the GNU General Public License v3

require 'mkmf'

$INCFLAGS = "#{ENV['EXTRA_INCFLAGS']} #{$INCFLAGS}"
$LDFLAGS = "#{ENV['EXTRA_LDFLAGS']} #{$LDFLAGS}"

if not ENV['LIBNOTMUCH']
  exit 1
end

$LOCAL_LIBS = ENV['LIBNOTMUCH']

# Create Makefile
dir_config('notmuch')
create_makefile('notmuch')
