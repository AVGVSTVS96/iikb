"use client";

import { useEffect, useRef, useState } from "react";

import { nothing } from "@/lib/bus";

interface Props {
  ours: number[];
  theirs: number[];
  block: number;
}

const H = 260;
const LEFT = 40;
const TOP = 12;
const BOTTOM = 30;

export const Chart = ({ ours, theirs, block }: Props) => {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [seen, setSeen] = useState(false);

  useEffect(() => {
    const el = ref.current;

    if (!el) {
      return nothing;
    }

    const ro = new ResizeObserver(([e]) => {
      setWidth(e?.contentRect.width ?? 0);
    });

    const io = new IntersectionObserver(
      ([e]) => {
        if (e?.isIntersecting === true) {
          setSeen(true);
          io.disconnect();
        }
      },
      { threshold: 0.35 },
    );

    ro.observe(el);
    io.observe(el);

    return () => {
      ro.disconnect();
      io.disconnect();
    };
  }, []);

  const narrow = width < 520;
  const height = narrow ? 200 : H;
  const right = narrow ? 8 : 150;

  const x = (i: number) => LEFT + (i / (ours.length - 1)) * (width - LEFT - right);
  const y = (v: number) => TOP + ((100 - v) / 20) * (height - TOP - BOTTOM);

  const path = (c: number[]) =>
    c.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join("");

  const last = ours.length - 1;

  const fade = seen ? "opacity-100 transition-opacity delay-300 duration-500" : "opacity-0";

  return (
    <div ref={ref} className="w-full" style={{ height }}>
      {width > 0 ? (
        <svg
          width={width}
          height={height}
          viewBox={`0 0 ${width} ${height}`}
          aria-hidden="true"
          className="overflow-visible"
        >
          {[80, 85, 90, 95, 100].map((v) => (
            <g key={v}>
              <line x1={LEFT} x2={width} y1={y(v)} y2={y(v)} className="stroke-border" />
              <text x={0} y={y(v) + 4} className="fill-faint font-mono text-[11px]">
                {v}%
              </text>
            </g>
          ))}
          {ours
            .map((_, i) => i)
            .filter((i) => (narrow ? i % 4 === 1 : i % 2 === 1))
            .map((i) => (
              <text
                key={i}
                x={x(i)}
                y={height - 6}
                textAnchor="middle"
                className="fill-faint font-mono text-[11px]"
              >
                {((i + 1) * block).toLocaleString("en-US")}
              </text>
            ))}
          <path
            d={path(theirs)}
            className={`fill-none stroke-faint [stroke-dasharray:4_5] [stroke-width:2] ${fade}`}
          />
          <path
            d={path(ours)}
            pathLength={1}
            className="fill-none stroke-pick [stroke-dasharray:1] [stroke-linecap:round] [stroke-width:2.5] transition-[stroke-dashoffset] duration-[800ms] ease-[cubic-bezier(0.4,0,0.2,1)]"
            style={{ strokeDashoffset: seen ? 0 : 1 }}
          />
          {ours.map((v, i) => (
            <circle key={`o${i}`} cx={x(i)} cy={y(v)} r={3} className={`fill-pick ${fade}`} />
          ))}
          {theirs.map((v, i) => (
            <circle key={`t${i}`} cx={x(i)} cy={y(v)} r={3} className={`fill-faint ${fade}`} />
          ))}
          {narrow ? null : (
            <text x={x(last) + 30} y={height - 6} className="fill-faint font-mono text-[11px]">
              words typed
            </text>
          )}
          {narrow ? (
            <>
              <text
                x={LEFT + 4}
                y={y(ours[0] ?? 0) - 10}
                className={`fill-pick font-mono text-xs ${fade}`}
              >
                iikb
              </text>
              <text
                x={LEFT + 4}
                y={y(theirs[0] ?? 0) + 22}
                className={`fill-faint font-mono text-xs ${fade}`}
              >
                nearest key + spell checker
              </text>
            </>
          ) : (
            <>
              <text
                x={x(last) + 12}
                y={y(ours[last] ?? 0) + 4}
                className={`fill-pick font-mono text-xs ${fade}`}
              >
                iikb
              </text>
              <text
                x={x(last) + 12}
                y={y(theirs[last] ?? 0) - 4}
                className={`fill-faint font-mono text-xs ${fade}`}
              >
                nearest key +
              </text>
              <text
                x={x(last) + 12}
                y={y(theirs[last] ?? 0) + 12}
                className={`fill-faint font-mono text-xs ${fade}`}
              >
                spell checker
              </text>
            </>
          )}
        </svg>
      ) : null}
    </div>
  );
};
