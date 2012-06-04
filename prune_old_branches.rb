#!/usr/bin/env ruby

require 'optparse'

$options = {
    :local => nil,
    :remote => nil,
    :specific_remotes => nil,
    :action => :list,
    :base => 'origin/develop',
    :exclude_patterns => ['(^|\/)develop$', '(^|\/)master$', '(^|\/)release$'],
    :include_patterns => []
}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby prune_old_branches.rb [options]"

  opts.on("-l", "--[no-]local", "Act on local branches.") do |v|
    $options[:local] = v
  end

  opts.on("-r", "--[no-]remote [REMOTE1[,REMOTE2]]", Array, "Act on remote branches; specify REMOTES to use specific remote repos.",
                                                 "  Use multiple times for multiple remotes.") do |v|
    $options[:remote] = !v.is_a?(FalseClass)
    $options[:specific_remotes] = v if $options[:remote]
  end

  opts.on("-l", "--[no-]local", "Act on local branches.") do |v|
    $options[:local] = v
  end

  opts.on("-a", "--all", "Act on all local and remote branches.",
                         "  Equivalent to -lr.") do
    $options[:local] = $options[:remote] = true
  end

  opts.on("-A", "--action ACTION", [:list, :ask, :delete], "What to do with old branches (list/ask/delete).", "  Defaults to list.") do |a|
    $options[:action] = a
  end

  opts.on("-b", "--base-branch BASE", "Branch to compare other branches with.",
                                      "  Defaults to origin/develop.") do |b|
    $options[:base] = b
  end

  opts.on("-e", "--exclude [PATTERN1[,PATTERN2]]", Array, "Exclude branches with a pattern from the list provided.",
                                                          "  Defaults to (^|\/)develop$,(^|\/)master$,(^|\/)release$.",
                                                          "  Use -e with no parameters to disable these exclusions.") do |list|
    $options[:exclude_patterns] = list || []
  end

  opts.on("-i", "--include [PATTERN1[,PATTERN2]]", Array, "Include only branches with a pattern from the list provided.",
                                                      "  If -e and -i conflict, the branch is excluded.") do |list|
    $options[:include_patterns] = list
  end

  opts.on_tail("-h", "--help", "Show this message.") do
    puts opts
    exit
  end
end.parse!
$options[:local] = true if $options[:local].nil? && $options[:remote].nil?

def branches
  puts "Identifying branches..."
  branches = []
  args = case
           when $options[:local] && $options[:remote]
             '-a'
           when $options[:remote]
             '-r'
           when $options[:local]
             '-l'
           else
             return []
         end

  output = `git branch #{args}`
  branches = output.lines.reject do |line|
    line =~ /HEAD/
  end.map do |line|
    stripped = line.strip.gsub(/\* /, "")
    if /^remotes\/(.*)/ =~ stripped
      Regexp.last_match(1)
    else
      stripped
    end
  end

  if $options[:include_patterns].any?
    # include only the specified branch patterns
    branches = branches.select do |branch|
      $options[:include_patterns].any? { |pattern| Regexp.new(pattern) =~ branch }
    end
  end

  if $options[:exclude_patterns].any?
    # exclude the specified branch patterns
    branches = branches.reject do |branch|
      $options[:exclude_patterns].any? { |pattern| Regexp.new(pattern) =~ branch }
    end
  end

  # exclude the base branch
  branches = branches.reject do |branch|
    $options[:base] == branch
  end

  if $options[:specific_remotes].respond_to? :select
    # include only branches from the specified remotes
    branches = branches.select do |branch|
      branch_remote(branch, $options[:specific_remotes])
    end
  end

  puts "Checking #{branches.count} branches for unmerged changes..."

  branches
end

def branch_remote(branch, specific_remotes=nil)
  specific_remotes ||= remotes
  specific_remotes.find {|remote| /^#{remote}\/.*/ =~ branch }
end

def has_changes?(branch)
  `git rev-list #{$options[:base]}..#{branch}`.lines.any?
end

def old_branches
  branches.reject { |branch| has_changes?(branch) }
end

def delete_branch(branch)
  if remote = branch_remote(branch)
    branch = /^#{remote}\/(.*)/.match(branch)[1]
    command = "git push #{remote} :#{branch}"
  else
    command = "git branch -D #{branch}"
  end
  puts command
  `#{command}`
end

def remotes
  $remotes ||= `git remote`.map { |remote| remote.strip }
end

def fetch
  puts "Fetching from #{remotes.count} remote#{remotes.count > 1 ? 's' : ''}..."
  remotes.each do |remote|
    `git fetch --prune #{remote}`
  end
end

def confirmed(branch)
  $stdout.write "Delete the branch '#{branch}'? [y/N]"
  r = $stdin.gets
  r.strip.downcase == "y"
end

def main
  fetch

  old_branches.each do |branch|
    puts "Branch '#{branch}' contains no changes that are not in #{$options[:base]}."
    if [:ask, :delete].include?($options[:action])
      if $options[:action] == :delete || confirmed(branch)
        delete_branch(branch)
      end
    end
  end

  puts "Finished."
end

main
