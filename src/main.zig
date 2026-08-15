const r4os = @import("r4os");
const AppApi = struct {
    sys: r4os.r4sys.Context,
    desk: r4os.r4desk.Context,
    draw: r4os.r4draw.Context,
    net: r4os.r4net.Context,
    dev: r4os.r4dev.Context,

    fn init(r4_app: *r4os.App) ?AppApi {
        return .{
            .sys = r4_app.system(),
            .desk = r4_app.desktop() orelse return null,
            .draw = r4_app.drawing() orelse return null,
            .net = r4_app.networkLowLevel() orelse return null,
            .dev = r4_app.devicesLowLevel() orelse return null,
        };
    }
};

const bg: u32 = 0xD8D0C8;
const panel: u32 = 0xF0F0F0;
const panel_dark: u32 = 0xC0C0C0;
const header: u32 = 0x0A246A;
const selected: u32 = 0x0A246A;
const text: u32 = 0x000000;
const text_inv: u32 = 0xFFFFFF;
const muted: u32 = 0x606060;

const max_records = 128;
const export_report_size = 16 * 1024;
const row_h = 18;
const bus_storage: u8 = 4;
const bus_network: u8 = 9;
const bus_protocol: u8 = 11;
const export_path = "C:\\Temp\\HWREPORT.TXT";
const network_tab_adapter: u8 = 0;
const network_tab_protocols: u8 = 1;
const network_tab_tcp: u8 = 2;
const filter_button_w = 64;
const filter_button_h = 20;
const detail_line_h = 18;

const device_palette = r4os.gui.Palette{
    .text = text,
    .disabled_text = muted,
    .face = bg,
    .face_light = 0xFFFFFF,
    .face_shadow = 0x808080,
    .client_bg = panel,
    .select_bg = selected,
    .select_text = text_inv,
    .title_bg = header,
    .title_text = text_inv,
};

const FilterMode = enum(u8) {
    all,
    driver,
    missing,
    network,
    storage,
    protocol,
};

const Layout = struct {
    root: r4os.gui.Rect,
    title: r4os.gui.Rect,
    summary: r4os.gui.Rect,
    filter: r4os.gui.Rect,
    content: r4os.gui.Rect,
    list: r4os.gui.Rect,
    details: r4os.gui.Rect,
};

pub fn r4_app_main(r4_app: *r4os.App) i32 {
    var ctx = AppApi.init(r4_app) orelse return r4os.abi.err_no_group;
    var app = App{ .ctx = &ctx };
    return app.run();
}

const App = struct {
    ctx: *AppApi,
    w: i32 = 640,
    h: i32 = 420,
    summary: r4os.abi.DeviceInventorySummary = .{},
    records: [max_records]r4os.abi.DeviceInventoryRecord = .{r4os.abi.DeviceInventoryRecord{}} ** max_records,
    visible_indices: [max_records]usize = .{0} ** max_records,
    count: usize = 0,
    visible_count: usize = 0,
    selected_index: usize = 0,
    first_visible: usize = 0,
    network_tab: u8 = network_tab_adapter,
    filter: FilterMode = .all,
    status: [64]u8 = .{0} ** 64,

    fn run(self: *App) i32 {
        const args = trim(zPtrSlice(self.ctx.sys.argsRaw()));
        if (equalsIgnoreCase(args, "/NETDETAIL") or equalsIgnoreCase(args, "NETDETAIL")) {
            self.ctx.sys.println("Device Manager");
            self.refresh();
            return self.printNetworkDetailSelftest();
        }
        if (equalsIgnoreCase(args, "/STORAGE") or equalsIgnoreCase(args, "STORAGE")) {
            self.ctx.sys.println("Device Manager");
            self.refresh();
            return self.printStorageSelftest();
        }

        if (self.ctx.desk.programWindowId() < 0) {
            self.ctx.sys.println("Device Manager");
            self.refresh();
            self.printConsole();
            if (self.exportReport()) {
                self.ctx.sys.println("Exported C:\\Temp\\HWREPORT.TXT");
            } else {
                self.ctx.sys.println("Export failed");
            }
            return 0;
        }

        _ = self.ctx.desk.guiSetTitle("Device Manager");
        _ = self.ctx.desk.guiSetMinSize(560, 360);
        var info: r4os.abi.GuiWindowInfo = .{};
        _ = self.ctx.desk.guiWindowInfo(&info);
        self.updateMetrics(info);
        self.refresh();
        self.render();

        while (!self.ctx.sys.programShouldClose()) {
            var event: r4os.abi.GuiEvent = .{};
            var dirty = false;
            while (self.ctx.desk.guiPollEvent(&event) > 0) {
                const kind: r4os.abi.GuiEventKind = @enumFromInt(event.kind);
                switch (kind) {
                    .close => return 0,
                    .resize => {
                        _ = self.ctx.desk.guiWindowInfo(&info);
                        self.updateMetrics(info);
                        dirty = true;
                    },
                    .key_down => {
                        const key: u8 = @intCast(event.key & 0xFF);
                        if (key == r4os.gui.Key.escape) return 0;
                        if (key == 'r' or key == 'R') {
                            self.refresh();
                            dirty = true;
                        } else if (key == 'e' or key == 'E') {
                            _ = self.exportReport();
                            dirty = true;
                        } else if (key == 'a' or key == 'A') {
                            self.setFilter(.all);
                            dirty = true;
                        } else if (key == 'n' or key == 'N') {
                            self.setFilter(.network);
                            dirty = true;
                        } else if (key == 'd' or key == 'D') {
                            self.setFilter(.driver);
                            dirty = true;
                        } else if (key == 'm' or key == 'M') {
                            self.setFilter(.missing);
                            dirty = true;
                        } else if (key == 's' or key == 'S') {
                            self.setFilter(.storage);
                            dirty = true;
                        } else if (key == 'p' or key == 'P') {
                            self.setFilter(.protocol);
                            dirty = true;
                        } else if (self.handleListKey(key)) {
                            dirty = true;
                        } else if (key == '1') {
                            self.network_tab = network_tab_adapter;
                            dirty = true;
                        } else if (key == '2') {
                            self.network_tab = network_tab_protocols;
                            dirty = true;
                        } else if (key == '3') {
                            self.network_tab = network_tab_tcp;
                            dirty = true;
                        } else if (self.handleNetworkTabKey(key)) {
                            dirty = true;
                        }
                    },
                    .mouse_down => {
                        if (self.exportButtonHit(event.x, event.y)) {
                            _ = self.exportReport();
                            dirty = true;
                        } else if (self.filterAt(event.x, event.y)) |filter| {
                            self.setFilter(filter);
                            dirty = true;
                        } else if (self.networkTabAt(event.x, event.y)) |tab| {
                            self.network_tab = tab;
                            dirty = true;
                        } else if (self.scrollListAt(event.x, event.y)) {
                            dirty = true;
                        } else if (self.indexAt(event.x, event.y)) |idx| {
                            self.selected_index = idx;
                            dirty = true;
                        }
                    },
                    else => {},
                }
            }
            if (dirty) self.render();
            self.ctx.sys.sleepTicks(3);
        }
        return 0;
    }

    fn updateMetrics(self: *App, info: r4os.abi.GuiWindowInfo) void {
        self.w = clamp(info.client_w, 420, 1600);
        self.h = clamp(info.client_h, 280, 1000);
    }

    fn refresh(self: *App) void {
        self.summary = .{};
        _ = self.ctx.dev.deviceInventorySummary(&self.summary);
        self.count = 0;
        var i: u32 = 0;
        while (i < self.summary.total and self.count < self.records.len) : (i += 1) {
            var rec: r4os.abi.DeviceInventoryRecord = .{};
            if (self.ctx.dev.deviceInventoryRecord(i, &rec) <= 0) break;
            self.records[self.count] = rec;
            self.count += 1;
        }
        self.sortRecords();
        self.applyFilter();
        if (self.count == 0) {
            self.selected_index = 0;
            self.first_visible = 0;
        } else if (self.selected_index >= self.count) self.selected_index = self.count - 1;
        self.ensureVisible();
    }

    fn printConsole(self: *App) void {
        self.ctx.sys.write("Summary: ");
        self.ctx.sys.printU64(self.summary.total);
        self.ctx.sys.write(" devices\r\n");
        self.printConsoleGroup(0);
        self.printConsoleGroup(1);
        self.printConsoleGroup(2);
    }

    fn printConsoleGroup(self: *App, binding: u8) void {
        self.ctx.sys.write(bindingName(binding));
        self.ctx.sys.write(":\r\n");
        var found = false;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.records[i].binding != binding) continue;
            found = true;
            self.ctx.sys.write("  ");
            self.ctx.sys.write(busName(self.records[i].bus));
            self.ctx.sys.write(" ");
            self.ctx.sys.write(zSlice(self.records[i].name[0..]));
            // PCI-Identitaet direkt in der Konsolenzeile: ohne Vendor-/
            // Device-ID ist ein "ohne Treiber"-/Unknown-Eintrag keine
            // brauchbare Treiber-Planungsgrundlage.
            if (self.records[i].vendor_id != 0 or self.records[i].device_id != 0) {
                var id_buf: [24]u8 = .{0} ** 24;
                var id_writer = Writer{ .out = id_buf[0..] };
                id_writer.text(" [");
                id_writer.hex16(self.records[i].vendor_id);
                id_writer.text(":");
                id_writer.hex16(self.records[i].device_id);
                id_writer.text("]");
                self.ctx.sys.write(id_writer.slice());
            }
            self.ctx.sys.write("  driver=");
            self.ctx.sys.write(nonEmpty(zSlice(self.records[i].driver[0..])));
            self.ctx.sys.write("  status=");
            self.ctx.sys.write(nonEmpty(zSlice(self.records[i].status[0..])));
            const note = zSlice(self.records[i].note[0..]);
            if (note.len > 0) {
                self.ctx.sys.write("  note=");
                self.ctx.sys.write(note);
            }
            self.ctx.sys.write("\r\n");
            if (self.records[i].bus == bus_network) {
                var detail_buf: [4096]u8 = .{0} ** 4096;
                var w = Writer{ .out = detail_buf[0..] };
                self.writeNetworkReport(&w, i);
                if (w.pos > 0) {
                    self.ctx.sys.write(w.slice());
                    self.ctx.sys.write("\r\n");
                }
            }
        }
        if (!found) self.ctx.sys.println("  none");
    }

    fn sortRecords(self: *App) void {
        var i: usize = 1;
        while (i < self.count) : (i += 1) {
            const rec = self.records[i];
            var j = i;
            while (j > 0 and recordSortKey(rec) < recordSortKey(self.records[j - 1])) : (j -= 1) {
                self.records[j] = self.records[j - 1];
            }
            self.records[j] = rec;
        }
    }

    fn printNetworkDetailSelftest(self: *App) i32 {
        self.ctx.sys.println("DEVMGR network detail selftest");
        const record_index = self.firstNetworkRecord() orelse {
            self.ctx.sys.println("DEVMGR netdetail: missing-network-adapter");
            return 1;
        };
        self.printFilterSelftestLine(.all, "filter all: ");
        self.printFilterSelftestLine(.network, "filter network: ");
        self.printFilterSelftestLine(.missing, "filter missing: ");
        self.printNetworkBackendMappingSelftest();
        var detail: r4os.abi.NetDetailSnapshot = .{};
        if (!self.networkDetail(record_index, &detail)) {
            self.ctx.sys.println("DEVMGR netdetail: netDetailGet failed");
            return 1;
        }

        var line: [144]u8 = .{0} ** 144;
        makeAdapterLine(line[0..], detail);
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeMacField(line[0..], "MAC", detail.adapter.mac);
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeIpv4Line(line[0..], detail);
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeRouteLine(line[0..], detail);
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeTrafficLine(line[0..], detail);
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeErrorLine(line[0..], detail, self.networkServiceErrors());
        self.printGeneratedLine("tab adapter: ", line[0..]);
        makeBackendLine(line[0..], detail);
        self.printGeneratedLine("tab adapter: ", line[0..]);

        makeArpLine(line[0..], detail);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        makeDhcpLine(line[0..], detail);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        makeDnsLine(line[0..], detail);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        makeTcpLine(line[0..], detail);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        makeProtocolLine(line[0..], detail);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        self.makeIpcSummaryLine(line[0..]);
        self.printGeneratedLine("tab protocols: ", line[0..]);
        self.makeIpcServicesLine(line[0..]);
        self.printGeneratedLine("tab protocols: ", line[0..]);

        makeTcpLine(line[0..], detail);
        self.printGeneratedLine("tab tcp: ", line[0..]);
        makeTcpConnectionLine(line[0..], detail);
        self.printGeneratedLine("tab tcp: ", line[0..]);
        const conn_count: usize = @intCast(detail.tcp_connection_count);
        var conn_index: usize = 0;
        while (conn_index < conn_count and conn_index < detail.tcp_connections.len) : (conn_index += 1) {
            makeTcpConnectionDetailLine(line[0..], detail.tcp_connections[conn_index], conn_index);
            self.printGeneratedLine("tab tcp: ", line[0..]);
        }

        self.ctx.sys.println("DEVMGR netdetail: ok");
        return 0;
    }

    fn printStorageSelftest(self: *App) i32 {
        self.ctx.sys.println("DEVMGR storage selftest");
        self.printFilterSelftestLine(.storage, "filter storage: ");

        var block_records: u32 = 0;
        var preload_blocks: u32 = 0;
        var mounted_c: u32 = 0;
        var builtin_blocks: u32 = 0;

        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const rec = self.records[i];
            if (rec.bus != bus_storage) continue;
            const is_block = !equalsIgnoreCase(zSlice(rec.driver[0..]), "storage/block");
            const source_preload = containsIgnoreCase(zSlice(rec.note[0..]), "source=preload");
            const source_disk = containsIgnoreCase(zSlice(rec.note[0..]), "source=disk");
            const source_builtin = containsIgnoreCase(zSlice(rec.note[0..]), "source=built-in") or containsIgnoreCase(zSlice(rec.note[0..]), "builtin storage");
            const rec_ok = !is_block or source_preload or source_disk;
            if (is_block) block_records += 1;
            if (is_block and source_preload) preload_blocks += 1;
            if (is_block and source_builtin) builtin_blocks += 1;
            if (is_block and source_preload and equalsIgnoreCase(zSlice(rec.status[0..]), "mounted-C")) mounted_c += 1;

            self.ctx.sys.write("DEVMGR storage ");
            self.ctx.sys.write(nonEmpty(zSlice(rec.name[0..])));
            self.ctx.sys.write(": ");
            self.ctx.sys.write(if (rec_ok) "OK" else "FAILED");
            self.ctx.sys.write(" driver=");
            self.ctx.sys.write(nonEmpty(zSlice(rec.driver[0..])));
            self.ctx.sys.write(" status=");
            self.ctx.sys.write(nonEmpty(zSlice(rec.status[0..])));
            const note = zSlice(rec.note[0..]);
            if (note.len > 0) {
                self.ctx.sys.write(" note=");
                self.ctx.sys.write(note);
            }
            self.ctx.sys.write("\r\n");
        }

        self.ctx.sys.write("DEVMGR storage records: blocks=");
        self.ctx.sys.printU64(block_records);
        self.ctx.sys.write(" preload=");
        self.ctx.sys.printU64(preload_blocks);
        self.ctx.sys.write(" mounted_c=");
        self.ctx.sys.printU64(mounted_c);
        self.ctx.sys.write(" builtin=");
        self.ctx.sys.printU64(builtin_blocks);
        self.ctx.sys.write("\r\n");

        const ok = block_records != 0 and preload_blocks != 0 and mounted_c != 0 and builtin_blocks == 0;
        self.ctx.sys.println(if (ok) "DEVMGR storage: ok" else "DEVMGR storage: failed");
        return if (ok) 0 else 1;
    }

    fn printFilterSelftestLine(self: *App, filter: FilterMode, prefix: []const u8) void {
        self.ctx.sys.write(prefix);
        self.ctx.sys.printU64(@intCast(filteredRecordCount(self.records[0..self.count], filter)));
        self.ctx.sys.write("\r\n");
    }

    fn printNetworkBackendMappingSelftest(self: *App) void {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.records[i].bus == bus_network or !isNetworkRelated(self.records[i])) continue;
            if (self.networkDetailRecordIndex(i)) |_| {
                self.ctx.sys.println("network backend map: ok");
                return;
            }
        }
        self.ctx.sys.println("network backend map: skipped");
    }

    fn printGeneratedLine(self: *App, prefix: []const u8, line: []const u8) void {
        self.ctx.sys.write(prefix);
        self.ctx.sys.write(zSlice(line));
        self.ctx.sys.write("\r\n");
    }

    fn firstNetworkRecord(self: *const App) ?usize {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.records[i].bus == bus_network and self.records[i].binding == 0) return i;
        }
        return null;
    }

    fn handleListKey(self: *App, key: u8) bool {
        if (self.visible_count == 0) return false;
        const pos = self.selectedVisiblePosition() orelse 0;
        const step = r4os.gui.selectionStepPaged(self.visible_count, self.visibleRows(), pos, key);
        if (step.action == .none) return false;
        self.selected_index = self.visible_indices[step.index];
        self.ensureVisible();
        return true;
    }

    fn handleNetworkTabKey(self: *App, key: u8) bool {
        if (self.visible_count == 0 or self.networkDetailRecordIndex(self.selected_index) == null) return false;
        const items = [_]r4os.gui.TabItem{
            .{ .text = "Adapter" },
            .{ .text = "Protocols" },
            .{ .text = "TCP" },
        };
        const result = (r4os.gui.TabBar{
            .rect = self.networkTabsRect(),
            .items = items[0..],
            .selected_index = self.network_tab,
        }).keyAction(key);
        if (result.action != .selection_changed) return false;
        self.network_tab = @intCast(result.index);
        return true;
    }

    fn ensureVisible(self: *App) void {
        const pos = self.selectedVisiblePosition() orelse {
            self.first_visible = 0;
            return;
        };
        _ = pos;
        self.first_visible = self.listHitTable().firstIndexForSelection();
    }

    fn visibleRows(self: *const App) usize {
        return @max(@as(usize, 1), self.listHitTable().visibleRows());
    }

    fn indexAt(self: *const App, x: i32, y: i32) ?usize {
        const visible_idx = self.listHitTable().indexAt(x, y) orelse return null;
        return if (visible_idx < self.visible_count) self.visible_indices[visible_idx] else null;
    }

    fn scrollListAt(self: *App, x: i32, y: i32) bool {
        const table = self.listHitTable();
        if (!table.needsScrollbar()) return false;
        const scrollbar = r4os.gui.Scrollbar{
            .rect = table.scrollbarRect(),
            .total_items = self.visible_count,
            .visible_items = self.visibleRows(),
            .first_index = self.first_visible,
        };
        const part = scrollbar.partAt(x, y);
        if (part == .none) return false;
        const step = scrollbar.step(part);
        if (step.action == .none) return false;
        self.first_visible = step.first_index;
        return true;
    }

    fn applyFilter(self: *App) void {
        self.visible_count = 0;
        var i: usize = 0;
        while (i < self.count and self.visible_count < self.visible_indices.len) : (i += 1) {
            if (!recordMatchesFilter(self.records[i], self.filter)) continue;
            self.visible_indices[self.visible_count] = i;
            self.visible_count += 1;
        }
        if (self.visible_count == 0) {
            self.first_visible = 0;
            return;
        }
        if (self.selectedVisiblePosition() == null) self.selected_index = self.visible_indices[0];
        self.ensureVisible();
    }

    fn setFilter(self: *App, filter: FilterMode) void {
        if (self.filter == filter) return;
        self.filter = filter;
        self.first_visible = 0;
        self.applyFilter();
    }

    fn selectedVisiblePosition(self: *const App) ?usize {
        var pos: usize = 0;
        while (pos < self.visible_count) : (pos += 1) {
            if (self.visible_indices[pos] == self.selected_index) return pos;
        }
        return null;
    }

    fn render(self: *App) void {
        var paint = switch (r4os.app_gui.beginPaintForSize(&self.ctx.draw, self.w, self.h)) {
            .paint => |value| value,
            .failure => return,
        };
        defer paint.discard();
        const canvas = paint.canvas;
        var scratch: [192]u8 = .{0} ** 192;
        const view_layout = self.layout();
        _ = canvas.clear(bg);
        _ = canvas.rect(view_layout.title, header);
        _ = canvas.label(.{ .rect = view_layout.title.inset(10, 6), .text = "Device Manager", .fg = text_inv, .bg = header, .palette = device_palette }, scratch[0..]);
        self.drawSummary(canvas, scratch[0..]);
        self.drawExportButton(canvas, scratch[0..]);
        self.drawFilterBar(canvas, scratch[0..]);
        self.drawList(canvas, scratch[0..]);
        self.drawDetails(canvas, scratch[0..]);
        _ = paint.present();
    }

    fn drawSummary(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        var buf: [96]u8 = .{0} ** 96;
        const rect = self.layout().summary;
        _ = canvas.rect(rect, panel);
        _ = canvas.rect(.{ .x = rect.x, .y = rect.bottom() - 1, .w = rect.w, .h = 1 }, panel_dark);
        makeSummary(buf[0..], self.summary);
        _ = canvas.label(.{ .rect = rect.inset(8, 4), .text = zSlice(buf[0..]), .fg = text, .bg = panel, .palette = device_palette }, scratch);
        const status_text = zSlice(self.status[0..]);
        if (status_text.len > 0) _ = canvas.label(.{ .rect = .{ .x = rect.x + 8, .y = rect.bottom() + 1, .w = rect.w - 16, .h = 14 }, .text = status_text, .fg = muted, .bg = bg, .palette = device_palette }, scratch);
    }

    fn drawExportButton(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.exportButtonRect();
        _ = canvas.toolbarButton(.{ .rect = rect, .text = "Export", .palette = device_palette }, scratch);
    }

    fn drawList(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        var title_device: [16]u8 = .{0} ** 16;
        var title_group: [16]u8 = .{0} ** 16;
        var title_bus: [16]u8 = .{0} ** 16;
        var title_status: [16]u8 = .{0} ** 16;
        const columns = [_]r4os.gui.TableColumn{
            .{ .title = copyLit(title_device[0..], "Device"), .width = @max(96, self.listTableBodyWidth() - 240), .alignment = .left },
            .{ .title = copyLit(title_group[0..], "Group"), .width = 76, .alignment = .left },
            .{ .title = copyLit(title_bus[0..], "Bus"), .width = 72, .alignment = .left },
            .{ .title = copyLit(title_status[0..], "Status"), .width = 92, .alignment = .left },
        };
        var cells: [max_records * 4][]const u8 = undefined;
        var names: [max_records][48]u8 = .{.{0} ** 48} ** max_records;
        var groups: [max_records][18]u8 = .{.{0} ** 18} ** max_records;
        var buses: [max_records][18]u8 = .{.{0} ** 18} ** max_records;
        var statuses: [max_records][28]u8 = .{.{0} ** 28} ** max_records;

        var row: usize = 0;
        while (row < self.visible_count) : (row += 1) {
            const rec = self.records[self.visible_indices[row]];
            copyBytes(names[row][0..], zSlice(rec.name[0..]));
            copyBytes(groups[row][0..], bindingName(rec.binding));
            copyBytes(buses[row][0..], busName(rec.bus));
            copyBytes(statuses[row][0..], nonEmpty(zSlice(rec.status[0..])));
            const base = row * 4;
            cells[base] = zSlice(names[row][0..]);
            cells[base + 1] = zSlice(groups[row][0..]);
            cells[base + 2] = zSlice(buses[row][0..]);
            cells[base + 3] = zSlice(statuses[row][0..]);
        }

        _ = canvas.tableView(.{
            .rect = self.listRect(),
            .columns = columns[0..],
            .cells = cells[0 .. self.visible_count * 4],
            .row_count = self.visible_count,
            .selected_index = self.selectedVisiblePosition() orelse 0,
            .first_index = self.first_visible,
            .row_h = row_h,
            .header_h = row_h,
            .palette = device_palette,
        }, scratch);
    }

    fn drawDetails(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const rect = self.detailsRect();
        if (rect.w < 120) return;
        _ = canvas.groupBox(.{ .rect = rect, .title = "Details", .palette = device_palette }, scratch);
        const inner = self.detailsInnerRect();
        if (self.visible_count == 0) {
            _ = canvas.label(.{ .rect = inner, .text = "No matching devices", .fg = muted, .bg = bg, .palette = device_palette }, scratch);
            return;
        }
        const rec = self.records[self.selected_index];
        var line: [128]u8 = .{0} ** 128;
        _ = canvas.label(.{ .rect = .{ .x = inner.x, .y = inner.y, .w = inner.w, .h = 16 }, .text = zSlice(rec.name[0..]), .fg = text, .bg = bg, .palette = device_palette }, scratch);
        makeField(line[0..], "Group", bindingName(rec.binding));
        self.drawDetailLine(canvas, scratch, inner.y + 24, zSlice(line[0..]), text);
        makeField(line[0..], "Bus", busName(rec.bus));
        self.drawDetailLine(canvas, scratch, inner.y + 42, zSlice(line[0..]), text);
        makeField(line[0..], "Driver", zSlice(rec.driver[0..]));
        self.drawDetailLine(canvas, scratch, inner.y + 60, zSlice(line[0..]), text);
        makeField(line[0..], "Status", zSlice(rec.status[0..]));
        self.drawDetailLine(canvas, scratch, inner.y + 78, zSlice(line[0..]), text);
        makePciLine(line[0..], rec);
        self.drawDetailLine(canvas, scratch, inner.y + 96, zSlice(line[0..]), muted);
        makeClassLine(line[0..], rec);
        self.drawDetailLine(canvas, scratch, inner.y + 114, zSlice(line[0..]), muted);
        if (self.networkDetailRecordIndex(self.selected_index)) |network_record_index| {
            self.drawNetworkTabs(canvas, scratch);
            self.drawNetworkDetails(canvas, scratch, network_record_index, rec);
        } else if (rec.bus == bus_protocol) {
            makeField(line[0..], "Protocol", zSlice(rec.note[0..]));
            self.drawDetailLine(canvas, scratch, inner.y + 140, zSlice(line[0..]), muted);
        } else {
            self.drawDetailLine(canvas, scratch, inner.y + 140, zSlice(rec.note[0..]), muted);
        }
    }

    fn layout(self: *const App) Layout {
        const root = r4os.gui.screenRect(self.w, self.h);
        var cursor = r4os.gui.LayoutCursor.init(root);
        const title = cursor.takeTop(28, 0);
        const body = r4os.gui.paddedRect(cursor.remaining(), 12);
        var body_cursor = r4os.gui.LayoutCursor.init(body);
        const summary = body_cursor.takeTop(28, 10);
        const filter = body_cursor.takeTop(filter_button_h, 8);
        const content = body_cursor.remaining();
        const list_w = @min(content.w, @max(220, @divTrunc(content.w * 55, 100)));
        const list = r4os.gui.Rect{ .x = content.x, .y = content.y, .w = list_w, .h = content.h };
        const details_gap: i32 = 12;
        const details = r4os.gui.Rect{
            .x = list.right() + details_gap,
            .y = content.y,
            .w = @max(0, content.right() - list.right() - details_gap),
            .h = content.h,
        };
        return .{ .root = root, .title = title, .summary = summary, .filter = filter, .content = content, .list = list, .details = details };
    }

    fn listRect(self: *const App) r4os.gui.Rect {
        return self.layout().list;
    }

    fn detailsRect(self: *const App) r4os.gui.Rect {
        return self.layout().details;
    }

    fn detailsInnerRect(self: *const App) r4os.gui.Rect {
        return self.detailsRect().inset(8, 16);
    }

    fn networkTabsRect(self: *const App) r4os.gui.Rect {
        const inner = self.detailsInnerRect();
        return .{ .x = inner.x, .y = inner.y + 136, .w = inner.w, .h = r4os.gui.default_metrics.tab_h + 2 };
    }

    fn networkDetailsRect(self: *const App) r4os.gui.Rect {
        const tabs = self.networkTabsRect();
        const inner = self.detailsInnerRect();
        return .{ .x = inner.x, .y = tabs.bottom() + 8, .w = inner.w, .h = @max(0, inner.bottom() - tabs.bottom() - 8) };
    }

    fn listHitTable(self: *const App) r4os.gui.TableView {
        return .{
            .rect = self.listRect(),
            .columns = &.{},
            .cells = &.{},
            .row_count = self.visible_count,
            .selected_index = self.selectedVisiblePosition() orelse 0,
            .first_index = self.first_visible,
            .row_h = row_h,
            .header_h = row_h,
            .palette = device_palette,
        };
    }

    fn listTableBodyWidth(self: *const App) i32 {
        const table = self.listHitTable();
        return r4os.gui.tableBodyRect(self.listRect(), row_h, table.needsScrollbar()).w;
    }

    fn exportButtonRect(self: *const App) r4os.gui.Rect {
        const summary = self.layout().summary;
        return .{ .x = summary.right() - 92, .y = summary.y + 4, .w = 84, .h = filter_button_h };
    }

    fn exportButtonHit(self: *const App, x: i32, y: i32) bool {
        return self.exportButtonRect().contains(x, y);
    }

    fn networkTabAt(self: *const App, x: i32, y: i32) ?u8 {
        if (self.visible_count == 0 or self.networkDetailRecordIndex(self.selected_index) == null) return null;
        const items = [_]r4os.gui.TabItem{
            .{ .text = "Adapter" },
            .{ .text = "Protocols" },
            .{ .text = "TCP" },
        };
        const index = (r4os.gui.TabBar{
            .rect = self.networkTabsRect(),
            .items = items[0..],
            .selected_index = self.network_tab,
            .palette = device_palette,
        }).indexAt(x, y) orelse return null;
        return @intCast(index);
    }

    fn drawFilterBar(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        self.drawFilterButton(canvas, scratch, .all, "All");
        self.drawFilterButton(canvas, scratch, .driver, "Driver");
        self.drawFilterButton(canvas, scratch, .missing, "NoDrv");
        self.drawFilterButton(canvas, scratch, .network, "Net");
        self.drawFilterButton(canvas, scratch, .storage, "Store");
        self.drawFilterButton(canvas, scratch, .protocol, "Proto");
        var line: [64]u8 = .{0} ** 64;
        var w = Writer{ .out = line[0..] };
        w.text("shown ");
        w.num(self.visible_count);
        w.text("/");
        w.num(self.count);
        const rect = self.layout().filter;
        _ = canvas.label(.{ .rect = .{ .x = rect.x + (filter_button_w + 4) * 6 + 8, .y = rect.y + 3, .w = @max(0, rect.right() - rect.x - (filter_button_w + 4) * 6 - 8), .h = rect.h }, .text = zSlice(line[0..]), .fg = muted, .bg = bg, .palette = device_palette }, scratch);
    }

    fn drawFilterButton(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, mode: FilterMode, label: []const u8) void {
        _ = canvas.toolbarButton(.{
            .rect = self.filterButtonRect(mode),
            .text = label,
            .selected = self.filter == mode,
            .palette = device_palette,
        }, scratch);
    }

    fn filterButtonRect(self: *const App, mode: FilterMode) r4os.gui.Rect {
        const bar = self.layout().filter;
        const step = filter_button_w + 4;
        const index: i32 = switch (mode) {
            .all => 0,
            .driver => 1,
            .missing => 2,
            .network => 3,
            .storage => 4,
            .protocol => 5,
        };
        return .{ .x = bar.x + step * index, .y = bar.y, .w = filter_button_w, .h = filter_button_h };
    }

    fn filterAt(self: *const App, x: i32, y: i32) ?FilterMode {
        const modes = [_]FilterMode{ .all, .driver, .missing, .network, .storage, .protocol };
        for (modes) |mode| {
            if ((r4os.gui.ToolbarButton{ .rect = self.filterButtonRect(mode), .text = "", .palette = device_palette }).contains(x, y)) return mode;
        }
        return null;
    }

    fn exportReport(self: *App) bool {
        var report: [export_report_size]u8 = .{0} ** export_report_size;
        var w = Writer{ .out = report[0..] };
        w.text("R4OS hardware report\r\n");
        w.text("====================\r\n\r\n");
        w.text("Summary: total=");
        w.num(self.summary.total);
        w.text(" with_driver=");
        w.num(self.summary.with_driver);
        w.text(" without_driver=");
        w.num(self.summary.without_driver);
        w.text(" unknown=");
        w.num(self.summary.unknown);
        w.text("\r\n\r\n");

        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const rec = self.records[i];
            w.text(bindingName(rec.binding));
            w.text("\r\n");
            w.text("  name=");
            w.text(zSlice(rec.name[0..]));
            w.text("\r\n  bus=");
            w.text(busName(rec.bus));
            if ((rec.flags & 1) != 0) {
                w.text(" addr=");
                w.num(rec.bus_no);
                w.text(":");
                w.num(rec.device_no);
                w.text(".");
                w.num(rec.function_no);
            }
            w.text("\r\n  vendor=");
            w.hex16(rec.vendor_id);
            w.text(" device=");
            w.hex16(rec.device_id);
            w.text(" class=");
            w.hex8(rec.class_code);
            w.text(" subclass=");
            w.hex8(rec.subclass);
            w.text(" prog_if=");
            w.hex8(rec.prog_if);
            w.text("\r\n  driver=");
            w.text(nonEmpty(zSlice(rec.driver[0..])));
            w.text(" status=");
            w.text(nonEmpty(zSlice(rec.status[0..])));
            const note = zSlice(rec.note[0..]);
            if (note.len > 0) {
                w.text("\r\n  note=");
                w.text(note);
            }
            if (rec.bus == bus_network) self.writeNetworkReport(&w, i);
            w.text("\r\n\r\n");
        }

        const data = w.slice();
        const written = self.ctx.sys.fileWrite(export_path, data);
        const ok_written = written == @as(i32, @intCast(data.len));
        if (ok_written and w.truncated) {
            self.setStatus("Exported C:\\Temp\\HWREPORT.TXT (truncated)");
        } else {
            self.setStatus(if (ok_written) "Exported C:\\Temp\\HWREPORT.TXT" else "Export failed");
        }
        return ok_written;
    }

    fn setStatus(self: *App, value: []const u8) void {
        @memset(self.status[0..], 0);
        var w = Writer{ .out = self.status[0..] };
        w.text(value);
    }

    fn drawDetailLine(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, y: i32, value: []const u8, fg: u32) void {
        const inner = self.detailsInnerRect();
        _ = canvas.label(.{ .rect = .{ .x = inner.x, .y = y, .w = inner.w, .h = detail_line_h }, .text = value, .fg = fg, .bg = bg, .palette = device_palette }, scratch);
    }

    fn drawNetworkTabs(self: *App, canvas: r4os.gui.Canvas, scratch: []u8) void {
        const items = [_]r4os.gui.TabItem{
            .{ .text = "Adapter" },
            .{ .text = "Protocols" },
            .{ .text = "TCP" },
        };
        _ = canvas.tabBar(.{
            .rect = self.networkTabsRect(),
            .items = items[0..],
            .selected_index = self.network_tab,
            .palette = device_palette,
        }, scratch);
    }

    fn drawNetworkDetails(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, record_index: usize, rec: r4os.abi.DeviceInventoryRecord) void {
        var detail: r4os.abi.NetDetailSnapshot = .{};
        var line: [144]u8 = .{0} ** 144;
        const rect = self.networkDetailsRect();
        if (!self.networkDetail(record_index, &detail)) {
            makeField(line[0..], "Network", zSlice(rec.note[0..]));
            self.drawNetworkLine(canvas, scratch, rect, 0, zSlice(line[0..]), muted);
            return;
        }

        var row: usize = 0;
        switch (self.network_tab) {
            network_tab_adapter => {
                makeAdapterLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), text);
                row += 1;
                makeMacField(line[0..], "MAC", detail.adapter.mac);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeIpv4Line(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeRouteLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeTrafficLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeErrorLine(line[0..], detail, self.networkServiceErrors());
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeBackendLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
            },
            network_tab_protocols => {
                makeArpLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), text);
                row += 1;
                makeDhcpLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeDnsLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeTcpLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                makeProtocolLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                self.makeIpcSummaryLine(line[0..]);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                self.makeIpcServicesLine(line[0..]);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
            },
            else => {
                makeTcpLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), text);
                row += 1;
                makeTcpConnectionLine(line[0..], detail);
                self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                row += 1;
                var conn_index: usize = 0;
                const conn_count: usize = @intCast(detail.tcp_connection_count);
                while (conn_index < conn_count and conn_index < detail.tcp_connections.len) : (conn_index += 1) {
                    makeTcpConnectionDetailLine(line[0..], detail.tcp_connections[conn_index], conn_index);
                    self.drawNetworkLine(canvas, scratch, rect, row, zSlice(line[0..]), muted);
                    row += 1;
                }
            },
        }
    }

    fn drawNetworkLine(self: *App, canvas: r4os.gui.Canvas, scratch: []u8, rect: r4os.gui.Rect, row: usize, value: []const u8, fg: u32) void {
        _ = self;
        const y = rect.y + @as(i32, @intCast(row)) * detail_line_h;
        if (y >= rect.bottom()) return;
        _ = canvas.label(.{ .rect = .{ .x = rect.x, .y = y, .w = rect.w, .h = detail_line_h }, .text = value, .fg = fg, .bg = bg, .palette = device_palette }, scratch);
    }

    fn writeNetworkReport(self: *App, w: *Writer, record_index: usize) void {
        var detail: r4os.abi.NetDetailSnapshot = .{};
        if (!self.networkDetail(record_index, &detail)) return;
        w.text("\r\n  network_detail:");
        w.text("\r\n    adapter=");
        w.text(zSlice(detail.adapter.name[0..]));
        w.text(" driver=");
        w.text(zSlice(detail.adapter.driver[0..]));
        w.text(" link=");
        w.text(zSlice(detail.adapter.link[0..]));
        w.text(" state=");
        w.text(zSlice(detail.adapter.state[0..]));
        w.text(" mtu=");
        w.num(detail.adapter.mtu);
        w.text("\r\n    mac=");
        w.mac(detail.adapter.mac);
        w.text(" ip=");
        w.ip(detail.config.local_ip);
        w.text(" mask=");
        w.ip(detail.config.netmask);
        w.text(" gateway=");
        w.ip(detail.config.gateway_ip);
        w.text(" dns=");
        w.ip(detail.config.dns_ip);
        w.text(" source=");
        w.text(zSlice(detail.config.source[0..]));
        w.text("\r\n    traffic rx=");
        w.num64(detail.adapter.rx_packets);
        w.text("/");
        w.num64(detail.adapter.rx_bytes);
        w.text(" tx=");
        w.num64(detail.adapter.tx_packets);
        w.text("/");
        w.num64(detail.adapter.tx_bytes);
        w.text(" drops=");
        w.num64(detail.adapter.drops);
        w.text(" errors=");
        w.num64(detail.adapter.errors);
        w.text(" last=");
        w.text(zSlice(detail.adapter.last_error[0..]));
        w.text("\r\n    errors total=");
        w.num64(networkErrorTotal(detail, self.networkServiceErrors()));
        w.text(" packet=");
        w.num64(networkPacketErrors(detail));
        w.text(" service=");
        w.num64(self.networkServiceErrors());
        w.text(" proto=");
        w.num64(networkProtocolErrors(detail));
        w.text(" last_proto=");
        w.text(lastProtocolError(detail));
        w.text(" registered=");
        w.num64(detail.adapter.registered_tick);
        w.text(" changed=");
        w.num64(detail.adapter.state_changed_tick);
        w.text("\r\n    backend irq_line=");
        if (detail.adapter.irq_line == 0xFF) w.text("-") else w.num(detail.adapter.irq_line);
        w.text(" registered=");
        w.text(if ((detail.flags & r4os.abi.net_detail_flag_irq_registered) != 0) "yes" else "no");
        w.text(" irq_count=");
        w.num64(detail.adapter.irq_count);
        w.text(" poll_count=");
        w.num64(detail.adapter.poll_count);
        w.text("\r\n    protocols eth=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_ethernet]);
        w.text(" arp=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_arp]);
        w.text(" ipv4=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_ipv4]);
        w.text(" icmp=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_icmp]);
        w.text(" udp=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_udp]);
        w.text(" dhcp=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_dhcp]);
        w.text(" dns=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_dns]);
        w.text(" tcp=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_tcp]);
        w.text(" r4sl=");
        writeRuntime(w, detail.protocols[r4os.abi.net_detail_protocol_serial_link]);
        self.writeIpcReport(w);
        w.text("\r\n    arp cache=");
        if ((detail.flags & r4os.abi.net_detail_flag_arp_cache_valid) != 0) {
            w.ip(detail.arp.cache_ip);
            w.text("=");
            w.mac(detail.arp.cache_mac);
        } else {
            w.text("empty");
        }
        w.text(" req_tx=");
        w.num64(detail.arp.requests_tx);
        w.text(" rep_rx=");
        w.num64(detail.arp.replies_rx);
        w.text(" age=");
        w.num64(detail.arp.cache_age_ticks);
        w.text("/");
        w.num64(detail.arp.cache_ttl_ticks);
        w.text("\r\n    dhcp bound=");
        w.text(if ((detail.flags & r4os.abi.net_detail_flag_dhcp_bound) != 0) "yes" else "no");
        w.text(" server=");
        w.ip(detail.dhcp.server_ip);
        w.text(" lease=");
        w.num(detail.dhcp.lease_seconds);
        w.text(" last=");
        w.text(zSlice(detail.dhcp.last_error[0..]));
        w.text("\r\n    dns queries=");
        w.num64(detail.dns.queries_tx);
        w.text(" responses=");
        w.num64(detail.dns.responses_rx);
        w.text(" server=");
        w.ip(detail.dns.last_server);
        w.text(" answer=");
        w.ip(detail.dns.last_answer);
        w.text(" last=");
        w.text(zSlice(detail.dns.last_error[0..]));
        w.text("\r\n    icmp dest_unreach=");
        w.num64(detail.icmp.destination_unreachable_rx);
        w.text(" port_unreach=");
        w.num64(detail.icmp.port_unreachable_rx);
        w.text(" time_exceeded=");
        w.num64(detail.icmp.time_exceeded_rx);
        w.text(" last=");
        w.text(zSlice(detail.icmp.last_error[0..]));
        w.text("\r\n    tcp active=");
        w.num(detail.tcp.active_connections);
        w.text("/");
        w.num(detail.tcp.max_connections);
        w.text(" listen=");
        w.num(detail.tcp.active_listeners);
        w.text(" tx=");
        w.num64(detail.tcp.data_tx);
        w.text(" rx=");
        w.num64(detail.tcp.data_rx);
        w.text(" retrans=");
        w.num64(detail.tcp.retransmits);
        w.text(" drops=");
        w.num64(detail.tcp.rx_drops);
        w.text(" last=");
        w.text(zSlice(detail.tcp_last_error[0..]));
        w.text("\r\n    tcp_connections=");
        w.num(detail.tcp_connection_count);
        const conn_count: usize = @intCast(detail.tcp_connection_count);
        var conn_index: usize = 0;
        while (conn_index < conn_count and conn_index < detail.tcp_connections.len) : (conn_index += 1) {
            const conn = detail.tcp_connections[conn_index];
            w.text("\r\n      #");
            w.num(conn_index);
            w.text(" id=");
            w.num(conn.id);
            w.text(" state=");
            w.text(tcpStateName(conn.state));
            w.text(" local=");
            w.num(conn.local_port);
            w.text(" remote=");
            w.ip(conn.remote_ip);
            w.text(":");
            w.num(conn.remote_port);
            w.text(" tx=");
            w.num64(conn.tx_bytes);
            w.text(" rx=");
            w.num64(conn.rx_bytes);
            w.text(" pending=");
            w.num(conn.pending_rx);
            w.text(" window=");
            w.num(conn.rx_window);
            w.text(" tx_window=");
            w.num(conn.tx_window);
            w.text(" retrans=");
            w.num(conn.retransmits);
            w.text(" drops=");
            w.num(conn.rx_drops);
        }
    }

    fn writeIpcReport(self: *App, w: *Writer) void {
        var summary: r4os.abi.IpcSummary = .{};
        if (self.ctx.dev.ipcSummary(&summary) <= 0) return;
        w.text("\r\n    ipc bus active=");
        w.num(summary.active_channels);
        w.text("/");
        w.num(summary.max_channels);
        w.text(" message_bytes=");
        w.num(summary.max_message_size);
        w.text(" queue_depth=");
        w.num(summary.queue_depth);
        w.text(" sends=");
        w.num64(summary.sends);
        w.text(" receives=");
        w.num64(summary.receives);
        w.text(" drops=");
        w.num64(summary.drops);
        w.text(" errors=");
        w.num64(summary.errors);

        var channel: u32 = 2;
        while (channel <= 5) : (channel += 1) {
            var info: r4os.abi.IpcChannelInfo = .{};
            _ = self.ctx.dev.ipcChannel(channel, &info);
            w.text("\r\n    ipc_service ");
            w.text(nonEmpty(zSlice(info.name[0..])));
            w.text(" channel=");
            w.num(channel);
            w.text(" active=");
            w.text(if (info.active != 0) "yes" else "no");
            w.text(" handler=");
            w.text(if (info.has_handler != 0) "yes" else "no");
            w.text(" queued=");
            w.num(info.queued);
            w.text("/");
            w.num(info.queue_depth);
            w.text(" sends=");
            w.num64(info.sends);
            w.text(" receives=");
            w.num64(info.receives);
            w.text(" drops=");
            w.num64(info.drops);
        }
    }

    fn makeIpcSummaryLine(self: *App, out: []u8) void {
        var b = Writer{ .out = out };
        var summary: r4os.abi.IpcSummary = .{};
        if (self.ctx.dev.ipcSummary(&summary) <= 0) {
            b.text("IPC: unavailable");
            return;
        }
        b.text("IPC: ch=");
        b.num(summary.active_channels);
        b.text("/");
        b.num(summary.max_channels);
        b.text(" msg=");
        b.num(summary.max_message_size);
        b.text(" q=");
        b.num(summary.queue_depth);
        b.text(" tx=");
        b.num64(summary.sends);
        b.text(" rx=");
        b.num64(summary.receives);
        b.text(" drop=");
        b.num64(summary.drops);
    }

    fn makeIpcServicesLine(self: *App, out: []u8) void {
        var b = Writer{ .out = out };
        b.text("Svc:");
        self.appendIpcService(&b, 2);
        self.appendIpcService(&b, 3);
        self.appendIpcService(&b, 4);
        self.appendIpcService(&b, 5);
    }

    fn appendIpcService(self: *App, b: *Writer, channel_id: u32) void {
        var info: r4os.abi.IpcChannelInfo = .{};
        _ = self.ctx.dev.ipcChannel(channel_id, &info);
        b.text(" ");
        b.text(shortServiceName(channel_id));
        b.text(" q");
        b.num(info.queued);
        b.text(" tx");
        b.num64(info.sends);
        b.text(" rx");
        b.num64(info.receives);
    }

    fn networkServiceErrors(self: *App) u64 {
        var total: u64 = 0;
        var channel_id: u32 = 2;
        while (channel_id <= 5) : (channel_id += 1) {
            var info: r4os.abi.IpcChannelInfo = .{};
            _ = self.ctx.dev.ipcChannel(channel_id, &info);
            total += info.drops;
        }
        return total;
    }

    fn networkDetail(self: *App, record_index: usize, out: *r4os.abi.NetDetailSnapshot) bool {
        if (record_index >= self.count) return false;
        if (self.records[record_index].bus != bus_network or self.records[record_index].binding != 0) return false;
        const adapter_index = self.networkAdapterIndex(record_index);
        return self.ctx.dev.netDetailGet(adapter_index, out) > 0;
    }

    fn networkDetailRecordIndex(self: *const App, record_index: usize) ?usize {
        if (record_index >= self.count) return null;
        const rec = self.records[record_index];
        if (rec.bus == bus_network and rec.binding == 0) return record_index;
        if (!isNetworkRelated(rec)) return null;

        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            const candidate = self.records[i];
            if (candidate.bus != bus_network or candidate.binding != 0) continue;
            if (samePciDevice(rec, candidate)) return i;
        }
        return null;
    }

    fn networkAdapterIndex(self: *const App, record_index: usize) u32 {
        var adapter_index: u32 = 0;
        var i: usize = 0;
        while (i < record_index and i < self.count) : (i += 1) {
            if (self.records[i].bus == bus_network and self.records[i].binding == 0) adapter_index += 1;
        }
        return adapter_index;
    }
};

fn makeSummary(out: []u8, s: r4os.abi.DeviceInventorySummary) void {
    var b = Writer{ .out = out };
    b.text("Total ");
    b.num(s.total);
    b.text("  with driver ");
    b.num(s.with_driver);
    b.text("  without driver ");
    b.num(s.without_driver);
    b.text("  unknown ");
    b.num(s.unknown);
}

fn recordMatchesFilter(rec: r4os.abi.DeviceInventoryRecord, filter: FilterMode) bool {
    return switch (filter) {
        .all => true,
        .driver => rec.binding == 0,
        .missing => rec.binding == 1,
        .network => isNetworkRelated(rec),
        .storage => rec.bus == bus_storage or rec.class_code == 0x01,
        .protocol => rec.bus == bus_protocol,
    };
}

fn filteredRecordCount(records: []const r4os.abi.DeviceInventoryRecord, filter: FilterMode) usize {
    var count: usize = 0;
    for (records) |rec| {
        if (recordMatchesFilter(rec, filter)) count += 1;
    }
    return count;
}

fn isNetworkRelated(rec: r4os.abi.DeviceInventoryRecord) bool {
    return rec.bus == bus_network or rec.class_code == 0x02;
}

fn samePciDevice(a: r4os.abi.DeviceInventoryRecord, b: r4os.abi.DeviceInventoryRecord) bool {
    if ((a.flags & 1) != 0 and (b.flags & 1) != 0) {
        return a.bus_no == b.bus_no and a.device_no == b.device_no and a.function_no == b.function_no;
    }
    return a.vendor_id != 0 and a.device_id != 0 and a.vendor_id == b.vendor_id and a.device_id == b.device_id;
}

fn makeField(out: []u8, label: []const u8, value: []const u8) void {
    var b = Writer{ .out = out };
    b.text(label);
    b.text(": ");
    if (value.len == 0) b.text("-") else b.text(value);
}

fn makePciLine(out: []u8, rec: r4os.abi.DeviceInventoryRecord) void {
    var b = Writer{ .out = out };
    if ((rec.flags & 1) == 0) {
        b.text("No PCI address");
        return;
    }
    b.text("PCI ");
    b.num(rec.bus_no);
    b.text(":");
    b.num(rec.device_no);
    b.text(".");
    b.num(rec.function_no);
    b.text("  VID ");
    b.hex16(rec.vendor_id);
    b.text(" DID ");
    b.hex16(rec.device_id);
}

fn makeClassLine(out: []u8, rec: r4os.abi.DeviceInventoryRecord) void {
    var b = Writer{ .out = out };
    b.text("Class ");
    b.hex8(rec.class_code);
    b.text(":");
    b.hex8(rec.subclass);
    b.text(":");
    b.hex8(rec.prog_if);
}

fn makeAdapterLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("Adapter: ");
    b.text(nonEmpty(zSlice(detail.adapter.name[0..])));
    b.text("  link=");
    b.text(nonEmpty(zSlice(detail.adapter.link[0..])));
    b.text("  state=");
    b.text(nonEmpty(zSlice(detail.adapter.state[0..])));
    b.text("  mtu=");
    b.num(detail.adapter.mtu);
}

fn makeMacField(out: []u8, label: []const u8, mac: [6]u8) void {
    var b = Writer{ .out = out };
    b.text(label);
    b.text(": ");
    b.mac(mac);
}

fn makeIpv4Line(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("IPv4: ");
    b.ip(detail.config.local_ip);
    b.text("  mask=");
    b.ip(detail.config.netmask);
    b.text("  src=");
    b.text(nonEmpty(zSlice(detail.config.source[0..])));
}

fn makeRouteLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("Route: gw=");
    b.ip(detail.config.gateway_ip);
    b.text("  dns=");
    if ((detail.flags & r4os.abi.net_detail_flag_dns_configured) != 0) b.ip(detail.config.dns_ip) else b.text("-");
}

fn makeTrafficLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("Traffic: rx=");
    b.num64(detail.adapter.rx_packets);
    b.text("/");
    b.num64(detail.adapter.rx_bytes);
    b.text("  tx=");
    b.num64(detail.adapter.tx_packets);
    b.text("/");
    b.num64(detail.adapter.tx_bytes);
    b.text("  drop=");
    b.num64(detail.adapter.drops);
    b.text(" err=");
    b.num64(detail.adapter.errors);
}

fn makeErrorLine(out: []u8, detail: r4os.abi.NetDetailSnapshot, service_errors: u64) void {
    var b = Writer{ .out = out };
    b.text("Errors: total=");
    b.num64(networkErrorTotal(detail, service_errors));
    b.text(" pkt=");
    b.num64(networkPacketErrors(detail));
    b.text(" svc=");
    b.num64(service_errors);
    b.text(" proto=");
    b.num64(networkProtocolErrors(detail));
    b.text(" last=");
    b.text(lastProtocolError(detail));
}

fn makeBackendLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("Backend: irq=");
    if (detail.adapter.irq_line == 0xFF) b.text("-") else b.num(detail.adapter.irq_line);
    b.text(" reg=");
    b.text(if ((detail.flags & r4os.abi.net_detail_flag_irq_registered) != 0) "yes" else "no");
    b.text(" hits=");
    b.num64(detail.adapter.irq_count);
    b.text(" poll=");
    b.num64(detail.adapter.poll_count);
}

fn makeArpLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("ARP: ");
    if ((detail.flags & r4os.abi.net_detail_flag_arp_cache_valid) != 0) {
        b.ip(detail.arp.cache_ip);
        b.text("=");
        b.mac(detail.arp.cache_mac);
    } else {
        b.text("cache empty");
    }
    b.text(" req=");
    b.num64(detail.arp.requests_tx);
    b.text(" rep=");
    b.num64(detail.arp.replies_rx);
    b.text(" age=");
    b.num64(detail.arp.cache_age_ticks);
    b.text("/");
    b.num64(detail.arp.cache_ttl_ticks);
    b.text(" hit=");
    b.num64(detail.arp.cache_hits);
    b.text(" res=");
    b.num64(detail.arp.resolve_attempts);
    b.text(" to=");
    b.num64(detail.arp.resolve_timeouts);
    b.text(" pend=");
    b.num64(detail.arp.pending_packets);
    b.text(" drop=");
    b.num64(detail.arp.pending_drops);
    b.text(" q=");
    b.num64(detail.arp.pending_queue_limit);
}

fn makeDhcpLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("DHCP: state=");
    b.text(dhcpRuntimeStateName(detail.dhcp.runtime_state));
    b.text(" linkGen=");
    b.num(detail.link_generation);
    b.text(" retry=");
    b.num(detail.adapter.dhcp_retry_round);
    b.text(" last=");
    b.text(nonEmpty(zSlice(detail.dhcp.last_error[0..])));
}

fn dhcpRuntimeStateName(value: u16) []const u8 {
    return switch (value) {
        0 => "disabled",
        1 => "static",
        2 => "wait-adapter",
        3 => "wait-link",
        4 => "acquire",
        5 => "retry-wait",
        6 => "bound",
        7 => "renew",
        8 => "rebind",
        9 => "lease-lost",
        else => "unknown",
    };
}

fn makeDnsLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("DNS: q=");
    b.num64(detail.dns.queries_tx);
    b.text(" resp=");
    b.num64(detail.dns.responses_rx);
    b.text(" srv=");
    b.ip(detail.dns.last_server);
    b.text(" ans=");
    b.ip(detail.dns.last_answer);
    b.text(" last=");
    b.text(nonEmpty(zSlice(detail.dns.last_error[0..])));
}

fn makeTcpLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("TCP: active=");
    b.num(detail.tcp.active_connections);
    b.text("/");
    b.num(detail.tcp.max_connections);
    b.text(" listen=");
    b.num(detail.tcp.active_listeners);
    b.text(" tx=");
    b.num64(detail.tcp.data_tx);
    b.text(" rx=");
    b.num64(detail.tcp.data_rx);
    b.text(" re=");
    b.num64(detail.tcp.retransmits);
    b.text(" drop=");
    b.num64(detail.tcp.rx_drops);
}

fn makeProtocolLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("R4P: eth=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_ethernet]));
    b.text(" arp=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_arp]));
    b.text(" ip=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_ipv4]));
    b.text(" udp=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_udp]));
    b.text(" dhcp=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_dhcp]));
    b.text(" dns=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_dns]));
    b.text(" tcp=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_tcp]));
    b.text(" r4sl=");
    b.text(runtimeSource(detail.protocols[r4os.abi.net_detail_protocol_serial_link]));
    b.text(" fail=");
    b.num64(protocolFailures(detail));
    b.text(" req=");
    b.num64(protocolRequiredCount(detail));
}

fn makeTcpConnectionLine(out: []u8, detail: r4os.abi.NetDetailSnapshot) void {
    var b = Writer{ .out = out };
    b.text("TCP conn: ");
    if (detail.tcp_connection_count == 0) {
        b.text("none");
        return;
    }
    const conn = detail.tcp_connections[0];
    b.text("#0 ");
    b.text(tcpStateName(conn.state));
    b.text(" local=");
    b.num(conn.local_port);
    b.text(" remote=");
    b.ip(conn.remote_ip);
    b.text(":");
    b.num(conn.remote_port);
    b.text(" rxq=");
    b.num(conn.pending_rx);
    if (detail.tcp_connection_count > 1) {
        b.text(" +");
        b.num(detail.tcp_connection_count - 1);
    }
}

fn makeTcpConnectionDetailLine(out: []u8, conn: r4os.abi.TcpConnectionInfo, index: usize) void {
    var b = Writer{ .out = out };
    b.text("#");
    b.num(index);
    b.text(" ");
    b.text(tcpStateName(conn.state));
    b.text(" local=");
    b.num(conn.local_port);
    b.text(" remote=");
    b.ip(conn.remote_ip);
    b.text(":");
    b.num(conn.remote_port);
    b.text(" q=");
    b.num(conn.pending_rx);
    b.text(" win=");
    b.num(conn.rx_window);
    b.text(" txwin=");
    b.num(conn.tx_window);
    b.text(" re=");
    b.num(conn.retransmits);
}

fn runtimeSource(value: r4os.abi.NetDetailProtocolRuntime) []const u8 {
    if (value.active_r4p != 0) return "r4p";
    if (value.builtin_fallback != 0) return "legacy";
    return switch (value.r4p_state) {
        r4os.abi.net_detail_r4p_state_missing => "miss",
        r4os.abi.net_detail_r4p_state_loaded => "load",
        r4os.abi.net_detail_r4p_state_blocked => "block",
        r4os.abi.net_detail_r4p_state_error => "err",
        r4os.abi.net_detail_r4p_state_disabled => "off",
        else => "unk",
    };
}

fn writeRuntime(w: *Writer, value: r4os.abi.NetDetailProtocolRuntime) void {
    w.text(runtimeSource(value));
    w.text("(rx=");
    w.num64(value.r4p_rx);
    w.text(" tx=");
    w.num64(value.r4p_tx);
    w.text(" ctl=");
    w.num64(value.r4p_control);
    w.text(" build=");
    w.num64(value.r4p_build);
    w.text(" cls=");
    w.num64(value.r4p_classify);
    w.text(" fail=");
    w.num64(value.dispatch_failures);
    w.text(" req=");
    w.text(requiredContractName(value));
    w.text(")");
}

fn requiredContractName(value: r4os.abi.NetDetailProtocolRuntime) []const u8 {
    if (value.builtin_fallback == 0 and
        value.fallback_policy == r4os.abi.net_detail_fallback_policy_none and
        value.fallback_decision == r4os.abi.net_detail_fallback_decision_none)
    {
        return "yes";
    }
    return "legacy";
}

fn networkPacketErrors(detail: r4os.abi.NetDetailSnapshot) u64 {
    return detail.adapter.drops +
        detail.adapter.errors +
        detail.ethernet.dropped_short +
        detail.ethernet.dropped_filter +
        detail.ethernet.unknown_ethertype +
        detail.arp.malformed +
        detail.arp.pending_drops +
        detail.ipv4.dropped_short +
        detail.ipv4.dropped_version +
        detail.ipv4.dropped_checksum +
        detail.ipv4.dropped_fragment +
        detail.ipv4.dropped_destination +
        detail.ipv4.dropped_tx_too_large +
        detail.ipv4.malformed +
        detail.icmp.malformed +
        detail.icmp.checksum_errors +
        detail.udp.dropped_short +
        detail.udp.dropped_length +
        detail.udp.checksum_errors +
        detail.udp.malformed +
        detail.dhcp.malformed +
        detail.dhcp.release_errors +
        detail.dns.malformed +
        detail.dns.tx_errors +
        detail.tcp.rx_drops +
        detail.tcp.checksum_errors;
}

fn networkProtocolErrors(detail: r4os.abi.NetDetailSnapshot) u64 {
    return detail.arp.resolve_timeouts +
        detail.arp.resolve_misses +
        detail.dns.timeouts +
        detail.dns.nxdomain +
        detail.tcp.timeouts +
        detail.tcp.rst_rx +
        protocolFailures(detail);
}

fn networkErrorTotal(detail: r4os.abi.NetDetailSnapshot, service_errors: u64) u64 {
    return networkPacketErrors(detail) + networkProtocolErrors(detail) + service_errors;
}

fn lastProtocolError(detail: r4os.abi.NetDetailSnapshot) []const u8 {
    const tcp_last = zSlice(detail.tcp_last_error[0..]);
    if (!equalsIgnoreCase(tcp_last, "none") and tcp_last.len != 0) return tcp_last;
    const dns_last = zSlice(detail.dns.last_error[0..]);
    if (!equalsIgnoreCase(dns_last, "none") and dns_last.len != 0) return dns_last;
    const udp_last = zSlice(detail.udp.last_error[0..]);
    if (!equalsIgnoreCase(udp_last, "none") and udp_last.len != 0) return udp_last;
    const ipv4_last = zSlice(detail.ipv4.last_error[0..]);
    if (!equalsIgnoreCase(ipv4_last, "none") and ipv4_last.len != 0) return ipv4_last;
    const adapter_last = zSlice(detail.adapter.last_error[0..]);
    if (adapter_last.len != 0) return adapter_last;
    return "none";
}

fn protocolFailures(detail: r4os.abi.NetDetailSnapshot) u64 {
    var total: u64 = 0;
    var i: usize = 0;
    while (i < detail.protocols.len) : (i += 1) total += detail.protocols[i].dispatch_failures;
    return total;
}

fn protocolRequiredCount(detail: r4os.abi.NetDetailSnapshot) u64 {
    var total: u64 = 0;
    var i: usize = 0;
    while (i < detail.protocols.len) : (i += 1) {
        if (detail.protocols[i].builtin_fallback == 0 and
            detail.protocols[i].fallback_policy == r4os.abi.net_detail_fallback_policy_none and
            detail.protocols[i].fallback_decision == r4os.abi.net_detail_fallback_decision_none)
        {
            total += 1;
        }
    }
    return total;
}

fn tcpStateName(value: u8) []const u8 {
    return switch (value) {
        0 => "closed",
        1 => "syn-sent",
        2 => "established",
        3 => "fin-wait",
        4 => "syn-received",
        else => "unknown",
    };
}

fn shortServiceName(channel_id: u32) []const u8 {
    return switch (channel_id) {
        2 => "dhcp",
        3 => "dns",
        4 => "tcp",
        5 => "udp",
        else => "ipc",
    };
}

const Writer = struct {
    out: []u8,
    pos: usize = 0,
    truncated: bool = false,

    fn put(self: *Writer, ch: u8) void {
        if (self.pos + 1 >= self.out.len) {
            self.truncated = true;
            return;
        }
        self.out[self.pos] = ch;
        self.pos += 1;
        self.out[self.pos] = 0;
    }

    fn text(self: *Writer, value: []const u8) void {
        for (value) |ch| if (ch != 0) self.put(ch);
    }

    fn slice(self: *const Writer) []const u8 {
        return self.out[0..self.pos];
    }

    fn num(self: *Writer, value: anytype) void {
        self.num64(@as(u64, @intCast(value)));
    }

    fn num64(self: *Writer, value: u64) void {
        var buf: [20]u8 = undefined;
        var pos: usize = buf.len;
        var n = value;
        if (n == 0) {
            self.put('0');
            return;
        }
        while (n > 0) {
            pos -= 1;
            buf[pos] = '0' + @as(u8, @intCast(n % 10));
            n /= 10;
        }
        self.text(buf[pos..]);
    }

    fn ip(self: *Writer, value: [4]u8) void {
        self.num(value[0]);
        self.put('.');
        self.num(value[1]);
        self.put('.');
        self.num(value[2]);
        self.put('.');
        self.num(value[3]);
    }

    fn mac(self: *Writer, value: [6]u8) void {
        var i: usize = 0;
        while (i < value.len) : (i += 1) {
            if (i != 0) self.put(':');
            self.hex8(value[i]);
        }
    }

    fn hex8(self: *Writer, value: u8) void {
        self.hexNibble(value >> 4);
        self.hexNibble(value & 0xF);
    }

    fn hex16(self: *Writer, value: u16) void {
        self.text("0x");
        self.hex8(@intCast(value >> 8));
        self.hex8(@intCast(value & 0xFF));
    }

    fn hexNibble(self: *Writer, value: u8) void {
        self.put(if (value < 10) '0' + value else 'A' + (value - 10));
    }
};

fn recordSortKey(rec: r4os.abi.DeviceInventoryRecord) u16 {
    return @as(u16, rec.binding) * 256 + rec.bus;
}

fn zSlice(buf: []const u8) []const u8 {
    var i: usize = 0;
    while (i < buf.len and buf[i] != 0) : (i += 1) {}
    return buf[0..i];
}

fn copyLit(out: []u8, comptime value: []const u8) []const u8 {
    copyBytes(out, value);
    return zSlice(out);
}

fn copyBytes(out: []u8, value: []const u8) void {
    if (out.len == 0) return;
    @memset(out, 0);
    const count = @min(value.len, out.len - 1);
    if (count > 0) @memcpy(out[0..count], value[0..count]);
    out[count] = 0;
}

fn zPtrSlice(ptr: [*:0]const u8) []const u8 {
    var i: usize = 0;
    while (ptr[i] != 0) : (i += 1) {}
    return ptr[0..i];
}

fn trim(value: []const u8) []const u8 {
    var start: usize = 0;
    var end = value.len;
    while (start < end and isSpace(value[start])) : (start += 1) {}
    while (end > start and isSpace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn equalsIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (toUpper(a[i]) != toUpper(b[i])) return false;
    }
    return true;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var start: usize = 0;
    while (start + needle.len <= haystack.len) : (start += 1) {
        if (equalsIgnoreCase(haystack[start..][0..needle.len], needle)) return true;
    }
    return false;
}

fn toUpper(ch: u8) u8 {
    return if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
}

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn nonEmpty(value: []const u8) []const u8 {
    return if (value.len == 0) "-" else value;
}

fn bindingName(value: u8) []const u8 {
    return switch (value) {
        0 => "Detected hardware with driver",
        1 => "Detected hardware without driver",
        else => "Unknown Device",
    };
}

fn busName(value: u8) []const u8 {
    return switch (value) {
        0 => "platform",
        1 => "acpi",
        2 => "pci",
        3 => "pcie",
        4 => "storage",
        5 => "display",
        6 => "audio",
        7 => "input",
        8 => "driver",
        9 => "network",
        10 => "usb",
        11 => "protocol",
        else => "unknown",
    };
}

fn clamp(value: i32, min: i32, max: i32) i32 {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}
