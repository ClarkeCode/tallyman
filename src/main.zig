const std = @import("std");

fn findFirstInstance(slice: []const u8, item: u8) ?usize {
	for (slice, 0..) |ch, i| {
		if (ch == item) return i;
	}
	return null;
}

///Returned buffer is allocated, responsibility of caller to free
fn readInfileToBuffer(allocator: std.mem.Allocator, fileName: []const u8) ![]const u8 {
	var buff: []u8 = undefined;
	//If the name is '-', input is from stdin
	if (std.mem.eql(u8, "-", fileName)) {
		buff = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
	}
	else {
		var file = try std.fs.cwd().openFile(fileName, .{});
		defer file.close();
		const fsize = (try file.stat()).size;
		buff = try file.readToEndAlloc(allocator, fsize);
	}

	return buff;
}

const TalliedItem = struct {
	count: usize,
	content: []const u8,

	pub fn lessThanComparator(_: void, lhs: TalliedItem, rhs: TalliedItem) bool {
		if (lhs.count < rhs.count) return true;
		if (lhs.count > rhs.count) return false;
		return std.mem.order(u8, lhs.content, rhs.content).compare(std.math.CompareOperator.lt);
	}

	pub fn greaterThanComparator(_: void, lhs: TalliedItem, rhs: TalliedItem) bool {
		if (lhs.count < rhs.count) return false;
		if (lhs.count > rhs.count) return true;
		return std.mem.order(u8, lhs.content, rhs.content).compare(std.math.CompareOperator.gt);
	}
};

const TallyOptions = struct {
	pub const SortOrder = enum { Descending, Ascending };
	sortOrder: SortOrder = .Descending,
};

///Returned slice is ordered according to TallyOptions. Returned slice is allocated, responsibility of caller to free.
fn tally(alloc: std.mem.Allocator, flatfile: []const u8, options: TallyOptions) ![]const TalliedItem {
	//TODO: It would be more efficient to insert lines directly into the StringHashMap, good enough for now
	var lines = std.ArrayList([]const u8).init(alloc);
	defer lines.deinit();
	var offset: usize = 0;
	while (true) {
		const next = findFirstInstance(flatfile[offset..], '\n');
		if (next) |n| {
			try lines.append(flatfile[offset..offset+n]);
			offset += n + 1;
		}
		else {
			break;
		}
	}
	if (flatfile[offset..].len > 0) {
		try lines.append(flatfile[offset..]);
	}

	var counter = std.StringHashMap(usize).init(alloc);
	defer counter.deinit();
	for (lines.items) |line| {
		if (counter.get(line)) |current| {
			try counter.put(line, current + 1);
		}
		else {
			try counter.put(line, 1);
		}
	}

	var aaa = std.ArrayList(TalliedItem).init(alloc);
	defer aaa.deinit();
	
	var it = counter.iterator();
	while (it.next()) |pair| {
		// std.debug.print("{d}\t{s}\n", .{pair.value_ptr.*, pair.key_ptr.*});
		try aaa.append(TalliedItem{.count = pair.value_ptr.*, .content = pair.key_ptr.*});
	}

	var oslice = try aaa.toOwnedSlice();
	switch (options.sortOrder) {
		.Descending => {std.sort.insertion(TalliedItem, oslice, {}, TalliedItem.greaterThanComparator);},
		.Ascending  => {std.sort.insertion(TalliedItem, oslice, {}, TalliedItem.lessThanComparator);},
	}
	return oslice;
}

fn printHelp(errMsg: ?[]const u8) void {
	if (errMsg) |message| {
		std.debug.print("ERROR: {s}\n\n", .{message});
	}
	std.debug.print("Usage: tallyman FILE\n", .{});
	std.debug.print("\tIf FILE is '-', read from stdin instead\n", .{});
}

pub fn main() !void {
	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();

	var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
	defer arena.deinit();
	var alloc = arena.allocator();

	//Print help message if file was not specified
	if (std.os.argv.len <= 1) {
		printHelp("Not enough arguments.");
		return;
	}

	//Aquire input file
	//TODO: add option parsing
	var infile: []const u8 = undefined;
	var index: usize = 1;
	while (index < std.os.argv.len) : (index += 1) {
		var offset: usize = 0;
		const len = while (true) { if (std.os.argv[index][offset] == 0) { break offset; } offset += 1;};
		infile = std.os.argv[index][0..len];
		break;
	}

	//Read in the file or print help message with the error
	const content = readInfileToBuffer(alloc, infile);
	if (content) |_| {}
	else |err| {
		printHelp(@errorName(err));
		return;
	}

	//Tally and output the results
	const outputLines = try tally(alloc, try content, .{});
	for (outputLines) |line| {
		try stdout.print("{d}\t{s}\n", .{line.count, line.content});
	}

	try bw.flush();
}
