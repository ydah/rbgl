# frozen_string_literal: true

# Fractured Orb (Metal Compute Shader)
# Original: https://www.shadertoy.com/view/ttycWW
# A mashup of 'Crystal Tetrahedron' and 'Buckyball Fracture'
# License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0
# https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'rbgl'
require 'rlsl'

WIDTH = 640
HEIGHT = 480

shader = RLSL.define_metal(:fractured_orb_metal) do
  uniforms do
    float :time
    float :rand_seed
  end

  helpers(:c) do
    <<~MSL
      #define PHI 1.618033988749895f
      #define PI 3.14159265359f
      #define TAU 6.28318530718f
      #define MAX_DISPERSE 5
      #define MAX_BOUNCE 10

      constant float OUTER = 0.35f;
      constant float INNER = 0.24f;

      // pR - 2D rotation
      float2 pR(float2 p, float a) {
        float c = cos(a), s = sin(a);
        return float2(c * p.x + s * p.y, -s * p.x + c * p.y);
      }

      // smax - smooth maximum
      float smax(float a, float b, float r) {
        float ua = max(r + a, 0.0f);
        float ub = max(r + b, 0.0f);
        return min(-r, max(a, b)) + sqrt(ua * ua + ub * ub);
      }

      // vmax
      float vmax2(float2 v) { return max(v.x, v.y); }
      float vmax3(float3 v) { return max(max(v.x, v.y), v.z); }

      // fBox - box SDF
      float fBox2(float2 p, float2 b) {
        float2 d = abs(p) - b;
        return length(max(d, float2(0))) + vmax2(min(d, float2(0)));
      }

      float fBox3(float3 p, float3 b) {
        float3 d = abs(p) - b;
        return length(max(d, float3(0))) + vmax3(min(d, float3(0)));
      }

      // erot - rotate on axis
      float3 erot(float3 p, float3 ax, float ro) {
        float d = dot(ax, p);
        float3 dax = ax * d;
        float c = cos(ro), s = sin(ro);
        return mix(dax, p, c) + s * cross(ax, p);
      }

      // Spectrum palette (IQ)
      float3 spectrum(float n) {
        float3 a = float3(0.5f);
        float3 b = float3(0.5f);
        float3 c = float3(1.0f);
        float3 d = float3(0.0f, 0.33f, 0.67f);
        return a + b * cos(TAU * (c * n + d));
      }

      // expImpulse
      float expImpulse(float x, float k) {
        float h = k * x;
        return h * exp(1.0f - h);
      }

      // boolSign
      float boolSign(float v) {
        return v > 0.0f ? 1.0f : -1.0f;
      }

      float3 boolSign3(float3 v) {
        return float3(boolSign(v.x), boolSign(v.y), boolSign(v.z));
      }

      // Icosahedron vertex (optimized by iq)
      float3 icosahedronVertex(float3 p) {
        float3 ap = abs(p);
        float3 v = float3(PHI, 1.0f, 0.0f);
        if (ap.x + ap.z * PHI > dot(ap, v)) v = float3(1.0f, 0.0f, PHI);
        if (ap.z + ap.y * PHI > dot(ap, v)) v = float3(0.0f, PHI, 1.0f);
        return v * 0.52573111f * boolSign3(p);
      }

      // Dodecahedron vertex (optimized by iq)
      float3 dodecahedronVertex(float3 p) {
        float3 ap = abs(p);
        float3 v = float3(PHI);
        float3 v2 = float3(0.0f, 1.0f, PHI + 1.0f);
        float3 v3 = v2.yzx;
        float3 v4 = v2.zxy;
        if (dot(ap, v2) > dot(ap, v)) v = v2;
        if (dot(ap, v3) > dot(ap, v)) v = v3;
        if (dot(ap, v4) > dot(ap, v)) v = v4;
        return v * 0.35682209f * boolSign3(p);
      }

      // Object SDF
      float object_sdf(float3 p) {
        float d = length(p) - OUTER;
        d = max(d, -d - (OUTER - INNER));
        return d;
      }

      // Map function
      float2 map(float3 p, float anim_time) {
        float scale = 2.5f;
        p /= scale;

        float outerBound = length(p) - OUTER;

        float spin = anim_time * (PI / 2.0f) - 0.15f;
        p.xz = pR(p.xz, spin);

        // Buckyball faces
        float3 va = icosahedronVertex(p);
        float3 vb = dodecahedronVertex(p);

        float side = boolSign(dot(p, cross(va, vb)));
        float r = TAU / 5.0f * side;
        float3 vc = erot(vb, va, r);
        float3 vd = erot(vb, va, -r);

        float d = 1e12f;
        float3 pp = p;

        for (int i = 0; i < 4; i++) {
          // Animation
          float t = fmod(anim_time * 2.0f / 3.0f + 0.25f - dot(va.xy, float2(1.0f, -1.0f)) / 30.0f, 1.0f);
          if (t < 0.0f) t += 1.0f;
          float t2 = clamp(t * 5.0f - 1.7f, 0.0f, 1.0f);
          float explode = 1.0f - pow(1.0f - t2, 10.0f);
          explode *= 1.0f - pow(t2, 5.0f);
          explode += (smoothstep(0.32f, 0.34f, t) - smoothstep(0.34f, 0.5f, t)) * 0.05f;
          explode *= 1.4f;
          t2 = max(t - 0.53f, 0.0f) * 1.2f;
          float wobble = sin(expImpulse(t2, 20.0f) * 2.2f + pow(3.0f * t2, 1.5f) * 2.0f * TAU - PI) * smoothstep(0.4f, 0.0f, t2) * 0.2f;
          float anim = wobble + explode;
          p -= va * anim / 2.8f;

          // Build boundary edge of face
          float edgeA = dot(p, normalize(vb - va));
          float edgeB = dot(p, normalize(vc - va));
          float edgeC = dot(p, normalize(vd - va));
          float edge = max(max(edgeA, edgeB), edgeC) - 0.005f;

          d = min(d, smax(object_sdf(p), edge, 0.002f));

          p = pp;

          // Cycle faces
          float3 va2 = va;
          va = vb; vb = vc; vc = vd; vd = va2;
        }

        float bound = outerBound - 0.002f;
        if (bound * scale > 0.002f) {
          d = min(d, bound);
        }

        return float2(d * scale, 1.0f);
      }

      // Normal calculation
      float3 calc_normal(float3 pos, float anim_time) {
        float3 n = float3(0.0f);
        for (int i = 0; i < 4; i++) {
          float3 e = 0.5773f * (2.0f * float3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0f);
          n += e * map(pos + 0.001f * e, anim_time).x;
        }
        return normalize(n);
      }

      // Spherical matrix multiply
      float3 sphericalMatrix_mul(float2 tp, float3 v) {
        float theta = tp.x, phi = tp.y;
        float cx = cos(theta), cy = cos(phi);
        float sx = sin(theta), sy = sin(phi);
        return float3(
          cy * v.x + (-sy * -sx) * v.y + (-sy * cx) * v.z,
          cx * v.y + sx * v.z,
          sy * v.x + (cy * -sx) * v.y + (cy * cx) * v.z
        );
      }

      // Light function
      float3 light_func(float3 origin, float3 rayDir, float2 envOrientation) {
        origin = -origin;
        rayDir = -rayDir;
        origin = sphericalMatrix_mul(envOrientation, origin);
        rayDir = sphericalMatrix_mul(envOrientation, rayDir);

        float3 pos = float3(-6.0f);
        float3 normal = normalize(pos);
        float3 up = normalize(float3(-1.0f, 1.0f, 0.0f));

        float denom = dot(rayDir, normal);
        if (abs(denom) < 0.0001f) return float3(0.0f);

        float t = dot(pos - origin, normal) / denom;
        if (t < 0.0f) return float3(0.0f);

        float3 point = origin + t * rayDir - pos;
        float3 tangent = cross(normal, up);
        float3 bitangent = cross(normal, tangent);
        float2 uv_l = float2(dot(tangent, point), dot(bitangent, point));

        float l = smoothstep(0.75f, 0.0f, fBox2(uv_l, float2(0.5f, 2.0f)) - 1.0f);
        l *= smoothstep(6.0f, 0.0f, length(uv_l));
        return float3(l);
      }

      // Environment function
      float3 env_func(float3 origin, float3 rayDir, float2 envOrientation) {
        origin = -origin;
        rayDir = -rayDir;
        origin = sphericalMatrix_mul(envOrientation, origin);
        rayDir = sphericalMatrix_mul(envOrientation, rayDir);

        float l = smoothstep(0.0f, 1.7f, dot(rayDir, float3(0.5f, -0.3f, 1.0f))) * 0.4f;
        return float3(0.9f, 0.83f, 1.0f) * l;
      }

      // Simple hash
      float simple_hash(float seed) {
        return fract(sin(seed * 12.9898f) * 43758.5453f);
      }
    MSL
  end

  fragment do
    <<~MSL
      float duration = 10.0f / 3.0f;
      float anim_time = fmod(u.time / duration, 1.0f);

      float2 envOrientation = (float2(81.5f / 187.0f, 119.0f / 187.0f) * 2.0f - 1.0f) * 2.0f;

      // Shadertoy-style centered UV: (fragCoord - resolution/2) / resolution.y
      float2 screen_uv = uv - float2(resolution.x / resolution.y * 0.5f, 0.5f);

      float3 col = float3(0.0f);
      float3 BGCOL = float3(0.9f, 0.83f, 1.0f);
      float3 bgCol = BGCOL * 0.22f;

      float maxDist = 30.0f;
      float3 camOrigin = float3(0.0f, 0.0f, 25.0f);
      float3 camDir = normalize(float3(screen_uv * 0.168f, -1.0f));

      // First march for depth
      float firstLen = 0.0f;
      float firstResY = 0.0f;
      float3 firstP = camOrigin;
      {
        float len = 0.0f;
        float dist = 0.0f;
        for (int i = 0; i < 300; i++) {
          len += dist * 0.8f;
          float3 p = camOrigin + len * camDir;
          float2 res = map(p, anim_time);
          dist = res.x;
          if (dist < 0.001f) { firstResY = res.y; break; }
          if (len >= maxDist) { len = maxDist; firstResY = 0.0f; break; }
        }
        firstLen = len;
        firstP = camOrigin + len * camDir;
      }

      // Dispersion loop
      for (int disperse = 0; disperse < MAX_DISPERSE; disperse++) {
        float invert = 1.0f;
        float3 sam = float3(0.0f);
        float3 origin = camOrigin;
        float3 rayDir = camDir;

        float extinctionDist = 0.0f;
        float wavelength = float(disperse) / float(MAX_DISPERSE);

        float rand = simple_hash(u.rand_seed + float(disperse) * 0.1f + uv.x * 100.0f + uv.y * 1000.0f);
        wavelength += (rand * 2.0f - 1.0f) * 0.1f;

        int bounceCount = 0;

        for (int bounce = 0; bounce < MAX_BOUNCE; bounce++) {
          float hitLen, hitResY;
          float3 p;

          if (bounce == 0) {
            hitLen = firstLen;
            hitResY = firstResY;
            p = firstP;
          } else {
            // March
            float len = 0.0f;
            float dist = 0.0f;
            hitResY = 0.0f;
            for (int mi = 0; mi < 300; mi++) {
              len += dist;
              p = origin + len * rayDir;
              float2 res = map(p, anim_time);
              dist = res.x * invert;
              if (dist < 0.001f) { hitResY = res.y; break; }
              if (len >= maxDist / 2.0f) { len = maxDist / 2.0f; hitResY = 0.0f; break; }
            }
            hitLen = len;
          }

          if (invert < 0.0f) {
            extinctionDist += hitLen;
          }

          if (hitResY == 0.0f) break;

          float3 nor = calc_normal(p, anim_time) * invert;
          float3 ref = reflect(rayDir, nor);

          // Shade
          sam += light_func(p, ref, envOrientation) * 0.5f;
          float fresnel = 1.0f - abs(dot(rayDir, nor));
          sam += pow(fresnel, 5.0f) * 0.1f;
          sam *= float3(0.85f, 0.85f, 0.98f);

          // Refract
          float ior = mix(1.2f, 1.8f, wavelength);
          ior = invert < 0.0f ? ior : 1.0f / ior;

          float3 raf = refract(rayDir, nor, ior);
          bool tif = (length(raf) < 0.001f);
          rayDir = tif ? ref : raf;

          float offset = 0.01f / (abs(dot(rayDir, nor)) + 0.0001f);
          origin = p + offset * rayDir;
          invert *= -1.0f;

          bounceCount = bounce;
        }

        sam += (bounceCount == 0) ? bgCol : env_func(firstP, rayDir, envOrientation);

        if (bounceCount == 0) {
          col += sam * float(MAX_DISPERSE) / 2.0f;
          break;
        } else {
          float3 spec = spectrum(-wavelength + 0.25f);
          col += sam * spec;
        }
      }

      col /= float(MAX_DISPERSE);

      // Tonemap
      col = pow(col, float3(1.25f)) * 2.5f;
      col = col / 2.0f * 16.0f;
      col = max(float3(0.0f), col - 0.004f);
      col = (col * (6.2f * col + 0.5f)) / (col * (6.2f * col + 1.7f) + 0.06f);

      return col;
    MSL
  end
end

# Initialize display
window = RBGL::GUI::Window.new(width: WIDTH, height: HEIGHT, title: 'Fractured Orb (Metal)')

unless window.metal_available?
  puts 'Metal is not available!'
  exit 1
end

puts 'Fractured Orb'
puts 'Original: https://www.shadertoy.com/view/ttycWW'
puts 'License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0'
puts 'https://creativecommons.org/licenses/by-nc-sa/3.0/deed.en'
puts "Press 'q' or Escape to quit"

start_time = Time.now
frame_count = 0
last_fps_time = start_time
running = true

while running && !window.should_close?
  time = Time.now - start_time
  rand_seed = rand * 1000.0

  begin
    shader.render_metal(window.native_handle, WIDTH, HEIGHT, { time: time, rand_seed: rand_seed })
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(10).join("\n")
    running = false
    break
  end

  events = window.poll_events_raw
  events.each do |e|
    running = false if e[:type] == :key_press && [12, 'q'].include?(e[:key])
  end

  frame_count += 1
  now = Time.now
  next unless now - last_fps_time >= 1.0

  fps = frame_count / (now - last_fps_time)
  puts "FPS: #{fps.round(1)}"
  frame_count = 0
  last_fps_time = now
end

window.close
