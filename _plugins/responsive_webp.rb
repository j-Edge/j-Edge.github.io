require "fileutils"

module Jekyll
  class ResponsiveWebpTag < Liquid::Tag
    def initialize(tag_name, markup, tokens)
      super
      @markup = markup.strip
    end

    def render(context)
      # Usage: {% responsive_webp img_path width="528" alt="..." class="..." lazy="true" %}
      tokens = @markup.scan(/(?:\w+="[^"]*"|\w+='[^']*'|\S)+/)
      path_token = tokens.shift.to_s
      raw_path = resolve_value(context, path_token).to_s.sub(%r{^/}, "")

      opts = {}
      tokens.each do |token|
        if token =~ /\A(\w+)=(["'])(.*)\2\z/
          opts[$1] = $3
        elsif token =~ /\A(\w+)=(\S+)\z/
          opts[$1] = resolve_value(context, $2).to_s
        end
      end

      site = context.registers[:site]
      baseurl = site.config["baseurl"].to_s.sub(%r{/$}, "")
      src_file = File.join(site.source, raw_path)
      return "" unless File.exist?(src_file)

      use_magick = system("magick -version >#{File::NULL} 2>&1")
      identify_cmd = use_magick ? ["magick", "identify"] : ["identify"]
      resize_cmd = use_magick ? ["magick"] : ["convert"]

      # Auto-detect intrinsic dimensions (e.g., "800 450")
      dims = IO.popen([*identify_cmd, "-format", "%w %h", src_file], &:read).to_s.split.map(&:to_i)
      orig_w, orig_h = dims
      return "" unless orig_w && orig_h && orig_w > 0 && orig_h > 0

      # Target desktop display width (defaults to original width if omitted)
      target_w = (opts["width"] ? opts["width"].to_i : orig_w)
      target_w = orig_w if target_w <= 0 || target_w > orig_w
      target_h = (target_w.to_f * orig_h / orig_w).round

      # Build responsive candidate widths: mobile (if wide enough), 1x target, 2x Retina, capped at orig_w
      candidates = [target_w, target_w * 2, orig_w]
      candidates.unshift(400) if target_w > 450
      widths = candidates.map { |w| [w, orig_w].min }.uniq.sort

      gen_dir = File.join(site.source, "assets", "generated")
      FileUtils.mkdir_p(gen_dir)
      base = File.basename(raw_path, File.extname(raw_path))

      srcset = widths.map do |w|
        out_name = "#{base}-#{w}.webp"
        out_file = File.join(gen_dir, out_name)

        if !File.exist?(out_file) || File.mtime(src_file) > File.mtime(out_file)
          system(*resize_cmd, src_file, "-resize", "#{w}x>", out_file)
        end

        already_registered = site.static_files.any? { |f| f.relative_path == "/assets/generated/#{out_name}" }
        unless already_registered
          site.static_files << Jekyll::StaticFile.new(site, site.source, "assets/generated", out_name)
        end

        "#{baseurl}/assets/generated/#{out_name} #{w}w"
      end

      fallback_w = widths.include?(target_w) ? target_w : widths.last
      sizes_attr = opts["sizes"] || "(max-width: 600px) 100vw, #{target_w}px"

      attrs = []
      attrs << %(class="#{opts['class']}") if opts["class"] && !opts["class"].empty?
      attrs << %(src="#{baseurl}/assets/generated/#{base}-#{fallback_w}.webp")
      attrs << %(srcset="#{srcset.join(', ')}")
      attrs << %(sizes="#{sizes_attr}")
      attrs << %(width="#{target_w}" height="#{target_h}")
      attrs << %(loading="lazy" decoding="async") if opts["lazy"] == "true"
      attrs << %(alt="#{opts['alt'].to_s.gsub('"', '&quot;')}")

      "<img #{attrs.join(' ')} />"
    end

    private

    def resolve_value(context, token)
      if token =~ /\A(["'])(.*)\1\z/
        $2
      else
        context[token]
      end
    end
  end
end

Liquid::Template.register_tag("responsive_webp", Jekyll::ResponsiveWebpTag)
