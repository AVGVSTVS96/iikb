type Listener = (value: string) => void;

const channel = () => {
  const listeners = new Set<Listener>();

  return {
    send: (value: string) => {
      for (const listen of listeners) {
        listen(value);
      }
    },
    listen: (listen: Listener) => {
      listeners.add(listen);

      return () => {
        listeners.delete(listen);
      };
    },
  };
};

export const dictation = channel();

export const theme = channel();

export const nothing = () => null;
