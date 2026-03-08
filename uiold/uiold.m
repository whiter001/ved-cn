#import <Cocoa/Cocoa.h>

typedef void (*ved_insert_text_fn)(void* user_data, const char* text);
typedef void (*ved_marked_text_fn)(void* user_data, const char* text);

static ved_insert_text_fn g_insert_cb = NULL;
static ved_marked_text_fn g_marked_cb = NULL;
static void* g_window_ptr = NULL;

@interface VedImeView : NSTextView
@end

@implementation VedImeView

- (void)commitInsertedText:(NSString *)text {
    if (text.length > 0 && g_insert_cb) {
        g_insert_cb(g_window_ptr, [text UTF8String]);
    }
    if (g_marked_cb) {
        g_marked_cb(g_window_ptr, "");
    }
    [self setString:@""];
    [self unmarkText];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    NSString *text = ([string isKindOfClass:[NSAttributedString class]]) ? [string string] : (NSString *)string;
    [self commitInsertedText:text];
}

- (void)paste:(id)sender {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length > 0) {
        [self commitInsertedText:text];
        return;
    }
    [super paste:sender];
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    [super setMarkedText:string selectedRange:selectedRange replacementRange:replacementRange];
    NSString *text = ([string isKindOfClass:[NSAttributedString class]]) ? [string string] : (NSString *)string;
    if (g_marked_cb) {
        g_marked_cb(g_window_ptr, [text UTF8String]);
    }
}

- (void)unmarkText {
    [super unmarkText];
    if (g_marked_cb) {
        g_marked_cb(g_window_ptr, "");
    }
}

- (void)doCommandBySelector:(SEL)selector {
    if (g_insert_cb) {
        if (selector == @selector(insertNewline:)) { g_insert_cb(g_window_ptr, "[ENTER]"); return; }
        if (selector == @selector(deleteBackward:)) { g_insert_cb(g_window_ptr, "[BACKSPACE]"); return; }
        if (selector == @selector(cancelOperation:)) { g_insert_cb(g_window_ptr, "[ESC]"); return; }
        if (selector == @selector(insertTab:)) { g_insert_cb(g_window_ptr, "[TAB]"); return; }
        if (selector == @selector(moveUp:)) { g_insert_cb(g_window_ptr, "[UP]"); return; }
        if (selector == @selector(moveDown:)) { g_insert_cb(g_window_ptr, "[DOWN]"); return; }
        if (selector == @selector(moveLeft:)) { g_insert_cb(g_window_ptr, "[LEFT]"); return; }
        if (selector == @selector(moveRight:)) { g_insert_cb(g_window_ptr, "[RIGHT]"); return; }
        if (selector == @selector(moveToBeginningOfLine:)) { g_insert_cb(g_window_ptr, "[HOME]"); return; }
        if (selector == @selector(moveToEndOfLine:)) { g_insert_cb(g_window_ptr, "[END]"); return; }
        if (selector == @selector(scrollPageUp:)) { g_insert_cb(g_window_ptr, "[PGUP]"); return; }
        if (selector == @selector(scrollPageDown:)) { g_insert_cb(g_window_ptr, "[PGDN]"); return; }
    }
    [super doCommandBySelector:selector];
}

- (BOOL)canBecomeKeyView { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    NSRect rect = [self bounds];
    if (actualRange) *actualRange = range;
    NSRect windowRect = [self convertRect:rect toView:nil];
    NSRect screenRect = [[self window] convertRectToScreen:windowRect];
    return screenRect;
}

@end

static VedImeView* g_ime_view = nil;

void setup_mac_app() {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app finishLaunching];
    [app activateIgnoringOtherApps:YES];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = [[NSApplication sharedApplication] keyWindow];
        if (window) {
            g_ime_view = [[VedImeView alloc] initWithFrame:NSMakeRect(-500, -500, 200, 20)];
            [g_ime_view setEditable:YES];
            [g_ime_view setRichText:NO];
            [g_ime_view setImportsGraphics:NO];
            [g_ime_view setContinuousSpellCheckingEnabled:NO];
            [g_ime_view setGrammarCheckingEnabled:NO];
            [g_ime_view setAutomaticQuoteSubstitutionEnabled:NO];
            [g_ime_view setAutomaticDashSubstitutionEnabled:NO];
            [g_ime_view setAutomaticTextReplacementEnabled:NO];
            [g_ime_view setDrawsBackground:NO];
            [g_ime_view setBackgroundColor:[NSColor clearColor]];
            [g_ime_view setTextColor:[NSColor clearColor]];
            [g_ime_view setInsertionPointColor:[NSColor clearColor]];
            [[window contentView] addSubview:g_ime_view];
        }
    });
}

void reg_ved_insert_cb(ved_insert_text_fn cb) { g_insert_cb = cb; }
void reg_ved_marked_cb(ved_marked_text_fn cb) { g_marked_cb = cb; }
void reg_ved_instance(void* ptr) { g_window_ptr = ptr; }

void set_ime_position(int x, int y, int h) {
    if (!g_ime_view) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = [g_ime_view window];
        if (window) {
            NSRect contentRect = [[window contentView] frame];
            float flippedY = contentRect.size.height - y - h;
            [g_ime_view setFrame:NSMakeRect(x, flippedY, 200, h)];
        }
    });
}

void focus_native_input(bool focus) {
    if (!g_ime_view) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = [g_ime_view window];
        if (window) {
            if (focus) [window makeFirstResponder:g_ime_view];
            else [window makeFirstResponder:[window contentView]];
        }
    });
}

void reg_key_ved2() {}