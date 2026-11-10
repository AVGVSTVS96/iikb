import { cn } from "@/lib/utils";

interface Props {
  name: string;
  alt: string;
  width: number;
  height: number;
  className?: string;
}

export const Shot = ({ name, alt, width, height, className }: Props) => (
  <picture>
    <source srcSet={`/shots/${name}-dark.webp`} media="(prefers-color-scheme: dark)" />
    <img
      src={`/shots/${name}-light.webp`}
      width={width}
      height={height}
      alt={alt}
      loading="lazy"
      className={cn("block h-auto w-full", className)}
    />
  </picture>
);

export const Phone = ({ name, alt }: { name: string; alt: string }) => (
  <div className="@container mx-auto w-full max-w-[360px]">
    <Shot
      name={name}
      alt={alt}
      width={804}
      height={1748}
      className="rounded-[13.5cqi] shadow-[0_0_0_1px_var(--border),0_0_0_5px_#0c0c0e,0_0_0_6px_#3a3a3e,0_40px_80px_-40px_rgb(0_0_0/0.4)]"
    />
  </div>
);

export const KeyboardShot = ({
  name,
  alt,
  height,
  className,
}: {
  name: string;
  alt: string;
  height: number;
  className?: string;
}) => (
  <div className={cn("@container", className)}>
    <Shot
      name={name}
      alt={alt}
      width={804}
      height={height}
      className="rounded-t-[8cqi] rounded-b-[12cqi]"
    />
  </div>
);
