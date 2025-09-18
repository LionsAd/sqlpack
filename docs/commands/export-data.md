# Export Data (BCP)

Exports table data using `bcp` in native format with `.fmt` files. Useful for advanced or selective data moves.

## Examples

```bash
# Export data for listed tables to ./data
BASH_LOG=info sqlpack export-data -s "localhost,1499" -d MyDb -D ./data -t ./tables.txt
```

`./tables.txt` should contain `Database.Schema.Table` names, one per line.

Tip: Use `BASH_LOG=trace` to stream each bcp command and its output.

Note: At `info`/`debug`, command output is captured to `.log` files next to the data/format files and summarized on errors. Use `trace` to stream everything to the console while still writing logs.
