--[[
Author: Wouter ten Brinke

Adds section-aware status bar items to KOReader:
- section progress
- section pages left
- section time to read
- section title

It also keeps chapter-based footer values aligned with level 1 TOC scope.
]]

local ReaderFooter = require("apps/reader/modules/readerfooter")
local userpatch = require("userpatch")
local _ = require("gettext")
local T = require("ffi/util").template

local MODE = userpatch.getUpValue(ReaderFooter.set_mode_index, "MODE")
local footerTextGeneratorMap = userpatch.getUpValue(ReaderFooter.updateFooterTextGenerator, "footerTextGeneratorMap")
local symbol_prefix = userpatch.getUpValue(ReaderFooter.textOptionTitles, "symbol_prefix")

-- Add section_time_to_read symbols if not already present
if symbol_prefix and not symbol_prefix.letters.section_time_to_read then
	local C_ = _.pgettext
	symbol_prefix.letters.section_time_to_read = C_("FooterLetterPrefix", "SC:")
	symbol_prefix.icons.section_time_to_read = "⤠"
	symbol_prefix.compact_items.section_time_to_read = "▾"
end

if MODE and not MODE.section_progress then
	MODE.section_progress = 22
end
if MODE and not MODE.section_time_to_read then
	MODE.section_time_to_read = 23
end
if MODE and not MODE.section_pages_left then
	MODE.section_pages_left = 24
end
if MODE and not MODE.section_title then
	MODE.section_title = 25
end

ReaderFooter.default_settings.section_progress = ReaderFooter.default_settings.section_progress or false
ReaderFooter.default_settings.section_time_to_read = ReaderFooter.default_settings.section_time_to_read or false
ReaderFooter.default_settings.section_pages_left = ReaderFooter.default_settings.section_pages_left or false
ReaderFooter.default_settings.section_title = ReaderFooter.default_settings.section_title or false

local function getTocRangeAtDepth(footer, pageno, wanted_depth)
	local toc = footer.ui.toc
	toc:fillToc()
	if not toc.toc or #toc.toc == 0 then
		return
	end

	local index = toc:getTocIndexByPage(pageno, false)
	if not index then
		return
	end

	while toc.toc[index + 1] and toc.toc[index + 1].page == pageno do
		index = index + 1
	end

	local scope_index
	for i = index, 1, -1 do
		local depth = toc.toc[i].depth
		if depth == wanted_depth then
			scope_index = i
			break
		elseif depth < wanted_depth then
			break
		end
	end
	if not scope_index then
		return
	end

	local start_page = toc.toc[scope_index].page
	local next_page = footer.ui.document:getPageCount() + 1
	for i = scope_index + 1, #toc.toc do
		if toc.toc[i].depth <= wanted_depth then
			next_page = toc.toc[i].page
			break
		end
	end

	return start_page, next_page
end

local function getRangeProgress(footer, pageno, start_page, next_page)
	local pages_done = pageno - start_page
	local page_count = next_page - start_page

	if page_count < 1 then
		page_count = 1
	end
	if pages_done < 0 then
		pages_done = 0
	elseif pages_done > page_count - 1 then
		pages_done = page_count - 1
	end

	if footer.ui.document:hasHiddenFlows() and footer.ui.document:getPageFlow(pageno) == 0 then
		for page = start_page, next_page - 1 do
			if footer.ui.document:getPageFlow(page) ~= 0 then
				page_count = page_count - 1
				if page < pageno then
					pages_done = pages_done - 1
				end
			end
		end
		if page_count < 1 then
			page_count = 1
			pages_done = 0
		end
		if pages_done < 0 then
			pages_done = 0
		end
	end

	local pages_left = page_count - pages_done - 1
	if footer.settings.pages_left_includes_current_page then
		pages_left = pages_left + 1
	end

	return pages_left, page_count, pages_done
end

local function getDepthScopedLeftAndTotal(footer, wanted_depth)
	local pageno = footer.pageno
	local start_page, next_page = getTocRangeAtDepth(footer, pageno, wanted_depth)
	if not start_page then
		return
	end
	return getRangeProgress(footer, pageno, start_page, next_page)
end

local function getSectionLeftAndTotal(footer)
	local toc = footer.ui.toc
	toc:fillToc()
	if not toc.toc or #toc.toc == 0 then
		return
	end

	local pageno = footer.pageno
	local start_page = 1
	local next_page = footer.ui.document:getPageCount() + 1

	for i = 1, #toc.toc do
		local page = toc.toc[i].page
		if page <= pageno then
			start_page = page
		else
			next_page = page
			break
		end
	end

	return getRangeProgress(footer, pageno, start_page, next_page)
end

local function cleanTocTitle(toc, title)
	if not title or title == "" then
		return nil
	end
	if toc.cleanUpTocTitle then
		return toc:cleanUpTocTitle(title, true)
	end
	return title
end

local function getTitleAtDepth(footer, wanted_depth)
	local toc = footer.ui.toc
	toc:fillToc()
	if not toc.toc or #toc.toc == 0 then
		return
	end

	local index = toc:getTocIndexByPage(footer.pageno, false)
	if not index then
		return
	end

	while toc.toc[index + 1] and toc.toc[index + 1].page == footer.pageno do
		index = index + 1
	end

	for i = index, 1, -1 do
		local entry = toc.toc[i]
		if entry.depth == wanted_depth then
			return cleanTocTitle(toc, entry.title)
		elseif entry.depth < wanted_depth then
			break
		end
	end
end

local function getSectionTitle(footer)
	return cleanTocTitle(footer.ui.toc, footer.ui.toc:getTocTitleByPage(footer.pageno))
end

if footerTextGeneratorMap then
	local function getPrefix(footer, key, fallback)
		if not symbol_prefix then return fallback end
		local s = symbol_prefix[footer.settings.item_prefix]
		return (s and s[key]) or fallback
	end

	local function getFallbackLeftAndTotal(footer)
		local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
		local total = footer.ui.toc:getChapterPageCount(footer.pageno) or footer.pages
		if footer.settings.pages_left_includes_current_page then
			left = left + 1
		end
		return left, total
	end

	local function getFallbackTimeLeft(footer)
		return footer.ui.toc:getChapterPagesLeft(footer.pageno, true) or footer.ui.document:getTotalPagesLeft(footer.pageno)
	end

	local function formatTimeLeft(footer, left)
		return getPrefix(footer, "chapter_time_to_read", ">>") .. " "
			.. (footer.ui.statistics and footer.ui.statistics:getTimeForPages(left) or _("N/A"))
	end

	local function formatSectionTimeLeft(footer, left)
		return getPrefix(footer, "section_time_to_read", "⤠") .. " "
			.. (footer.ui.statistics and footer.ui.statistics:getTimeForPages(left) or _("N/A"))
	end

	local function formatPagesLeft(footer, left)
		return getPrefix(footer, "pages_left", ">") .. " " .. left
	end

	local function formatTitle(footer, title)
		if not title or title == "" then
			return ""
		end
		local max_pct = math.max((footer.settings and footer.settings.book_chapter_max_width_pct) or 30, 80)
		if footer.getFittedText then
			return footer:getFittedText(title, max_pct)
		end
		return title
	end

	footerTextGeneratorMap.chapter_progress = function(footer)
		local left, total, done = getDepthScopedLeftAndTotal(footer, 1)
		if not left then
			left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
			total = footer.ui.toc:getChapterPageCount(footer.pageno) or footer.pages
			done = total - left
		end
		local symbol = getPrefix(footer, "chapter_progress", "⁄⁄")
		local read = math.min(done + 1, total)
		return read .. " " .. symbol .. " " .. total
	end

	footerTextGeneratorMap.section_progress = function(footer)
		local left, total, done = getSectionLeftAndTotal(footer)
		if not left then
			left, total = getFallbackLeftAndTotal(footer)
			done = total - left
		end
		local symbol = getPrefix(footer, "section_progress", "⁄⁄⁄")
		local read = math.min(done + 1, total)
		return read .. " " .. symbol .. " " .. total
	end

	footerTextGeneratorMap.pages_left = function(footer)
		local left = getDepthScopedLeftAndTotal(footer, 1)
		if not left then
			left = footer.ui.toc:getChapterPagesLeft(footer.pageno)
				or footer.ui.document:getTotalPagesLeft(footer.pageno)
			if footer.settings.pages_left_includes_current_page then
				left = left + 1
			end
		end
		return formatPagesLeft(footer, left)
	end

	footerTextGeneratorMap.section_pages_left = function(footer)
		local left = getSectionLeftAndTotal(footer)
		if not left then
			left = footer.ui.toc:getChapterPagesLeft(footer.pageno)
				or footer.ui.document:getTotalPagesLeft(footer.pageno)
			if footer.settings.pages_left_includes_current_page then
				left = left + 1
			end
		end
		return formatPagesLeft(footer, left)
	end

	footerTextGeneratorMap.section_time_to_read = function(footer)
		local left = getSectionLeftAndTotal(footer)
		if not left then left = getFallbackTimeLeft(footer) end
		return formatSectionTimeLeft(footer, left)
	end

	footerTextGeneratorMap.chapter_time_to_read = function(footer)
		local left = getDepthScopedLeftAndTotal(footer, 1)
		if not left then left = getFallbackTimeLeft(footer) end
		return formatTimeLeft(footer, left)
	end

	footerTextGeneratorMap.book_chapter = function(footer)
		return formatTitle(footer, getTitleAtDepth(footer, 1))
	end

	footerTextGeneratorMap.section_title = function(footer)
		return formatTitle(footer, getSectionTitle(footer))
	end
end

local orig_ReaderFooter_textOptionTitles = ReaderFooter.textOptionTitles

ReaderFooter.textOptionTitles = function(self, option)
	if option == "section_pages_left" then
		local symbol = self.settings and self.settings.item_prefix or "icons"
		local prefix = symbol_prefix and symbol_prefix[symbol] and symbol_prefix[symbol].pages_left or ">"
		return T(_("Pages left in section (%1)"), prefix)
	elseif option == "section_progress" then
		return _("Pages read in section (⁄⁄⁄)")
	elseif option == "section_time_to_read" then
		local symbol = self.settings and self.settings.item_prefix or "icons"
		local section_symbol = symbol_prefix and symbol_prefix[symbol] and symbol_prefix[symbol].section_time_to_read or "⤠"
		return T(_("Time left to finish section (%1)"), section_symbol)
	elseif option == "section_title" then
		return _("Section title")
	end
	return orig_ReaderFooter_textOptionTitles(self, option)
end

local function findMenuItemByLabel(sub_items, label)
	for i, item in ipairs(sub_items) do
		if item.label == label then
			return item, i
		end
	end
end

local function findMenuItem(sub_items, text)
	for i, item in ipairs(sub_items) do
		local item_text = item.text or (item.text_func and item.text_func())
		if item_text == text then
			return item, i
		end
	end
end

local function findNodeByText(node, text)
	if not node or not node.sub_item_table then
		return
	end
	local found = findMenuItem(node.sub_item_table, text)
	if found then
		return found
	end
	for _, item in ipairs(node.sub_item_table) do
		if item.sub_item_table then
			local nested = findNodeByText(item, text)
			if nested then
				return nested
			end
		end
	end
end

local function ensureInserted(list, item, marker_text, item_title, item_label)
	local _, existing_index = item_label and findMenuItemByLabel(list, item_label) or findMenuItem(list, item_title)
	if existing_index then
		return
	end
	local marker_index = marker_text and select(2, findMenuItem(list, marker_text)) or nil
	if marker_index then
		table.insert(list, marker_index + 1, item)
	else
		table.insert(list, item)
	end
end

local function toggleFooterOption(footer, option_name)
	footer.settings[option_name] = not footer.settings[option_name]

	local prev_has_no_mode = footer.has_no_mode
	local first_enabled_mode_num = footer:set_has_no_mode()
	local should_update = false

	if footer.has_no_mode then
		footer.footer_text.height = 0
		footer.mode = footer.mode_list.off
		should_update = true
	elseif prev_has_no_mode then
		if footer.settings.all_at_once then
			footer.mode = footer.mode_list.page_progress
			footer:applyFooterMode()
			G_reader_settings:saveSetting("reader_footer_mode", footer.mode)
		else
			G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
		end
		should_update = true
	elseif footer.settings.all_at_once then
		should_update = footer:updateFooterTextGenerator()
	elseif (footer.mode_list[option_name] == footer.mode and footer.settings[option_name] == false)
			or (prev_has_no_mode ~= footer.has_no_mode) then
		if not footer.has_no_mode then
			footer.mode = first_enabled_mode_num
		else
			footer.mode = footer.settings.disable_progress_bar and footer.mode_list.off or footer.mode_list.page_progress
		end
		should_update = true
		footer:applyFooterMode()
		G_reader_settings:saveSetting("reader_footer_mode", footer.mode)
	end

	if should_update then
		footer:refreshFooter(true, true)
	end
	footer:rescheduleFooterAutoRefreshIfNeeded()
end

local function newToggleMenuItem(self, option_name, help_text)
	return {
		label = option_name,
		text_func = function()
			return self:textOptionTitles(option_name)
		end,
		help_text = help_text,
		checked_func = function()
			return self.settings[option_name] == true
		end,
		callback = function()
			toggleFooterOption(self, option_name)
		end,
	}
end

local orig_ReaderFooter_addToMainMenu = ReaderFooter.addToMainMenu

ReaderFooter.addToMainMenu = function(self, menu_items)
	orig_ReaderFooter_addToMainMenu(self, menu_items)

	local status_bar_items = findNodeByText(menu_items.status_bar, _("Status bar items"))
	if status_bar_items and status_bar_items.sub_item_table then
		local section_item = newToggleMenuItem(
			self,
			"section_progress",
			_("Shows pages read and total for the current section, independent from chapter progress.")
		)
		ensureInserted(
			status_bar_items.sub_item_table,
			newToggleMenuItem(self, "section_title",
				_("Shows the current section title.")),
			self:textOptionTitles("section_progress"),
			self:textOptionTitles("section_title"),
			"section_title"
		)
		ensureInserted(
			status_bar_items.sub_item_table,
			newToggleMenuItem(self, "section_pages_left",
				_("Pages left in the current section.")),
			self:textOptionTitles("pages_left"),
			self:textOptionTitles("section_pages_left")
		)
		ensureInserted(
			status_bar_items.sub_item_table,
			section_item,
			self:textOptionTitles("chapter_progress"),
			self:textOptionTitles("section_progress")
		)

		local section_time_item = newToggleMenuItem(
			self,
			"section_time_to_read",
			_("Shows estimated time left to finish the current section.")
		)
		ensureInserted(
			status_bar_items.sub_item_table,
			section_time_item,
			self:textOptionTitles("chapter_time_to_read"),
			self:textOptionTitles("section_time_to_read")
		)
	end

	local configure_items = findNodeByText(menu_items.status_bar, _("Configure items"))
	if configure_items and configure_items.sub_item_table then
		local include_current = findMenuItem(configure_items.sub_item_table, _("Include current page in pages left"))
		if include_current then
			include_current.enabled_func = function()
				return self.settings.pages_left or self.settings.pages_left_book
					or self.settings.section_progress or self.settings.section_pages_left
			end
		end
	end
end
