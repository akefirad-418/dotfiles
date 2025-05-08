global.lpad = (x, n) => x.toString().padStart(n, ' ');
global.rpad = (x, n) => x.toString().padEnd(n, ' ');
global.lfit = (x, n) => lpad(x.toString().slice(-n), n);
global.rfit = (x, n) => rpad(x.toString().slice(0, n), n);

global.parseWpK8sLog = x => {
    const tryCatch = (f, x) => {
        try {
            return f(x);
        } catch (e) {
            return x;
        }
    }
  const { ts, request_id, level, logger, message } = x;
  const fmtTimestamp = tryCatch(x => new Date(x).toISOString(), ts);
  const fmtLevel = tryCatch(x => lpad(x, 5), level);
  const fmtLogger = tryCatch(x => lfit(x, 30), logger);
  const color = level === 'INFO' ? '\x1b[32m' : level === 'WARN' ? '\x1b[33m' : level === 'ERROR' ? '\x1b[31m' : '\x1b[0m';
  return `${color}${fmtTimestamp} ${request_id} ${fmtLevel} ${fmtLogger} ${message}\x1b[0m`;
};
