const fs = require('fs');
try {
  JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  process.exit(0);
} catch (e) {
  process.exit(1);
}
