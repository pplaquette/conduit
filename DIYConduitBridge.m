//
//  DIYConduitBridge.m
//  conduit
//
//  Created by Andrew Sliwinski on 6/17/12.
//  Based on WebViewJavascriptBridge by Marcus Westin, Stepan Generalov and Sergio Campamá.
//

#import "DIYConduitBridge.h"

//

@interface DIYConduitBridge ()
@property (nonatomic,strong) NSMutableArray *startupMessageQueue;
- (void)_flushMessageQueueFromWebView:(UIWebView *)webView;
- (void)_doSendMessage:(NSString*)message toWebView:(UIWebView *)webView;
@end

//

@implementation DIYConduitBridge

@synthesize delegate = _delegate;
@synthesize requestHeaders = _requestHeaders;
@synthesize startupMessageQueue = _startupMessageQueue;

static NSString *MESSAGE_SEPARATOR      = @"__wvjb_sep__";
static NSString *CUSTOM_PROTOCOL_SCHEME = @"webviewjavascriptbridge";
static NSString *QUEUE_HAS_MESSAGE      = @"queuehasmessage";

#pragma mark - Init

- (id)init
{
    self = [super init];
    if (self) {
        [self resetQueue];
    }
    return self;
}

#pragma mark - Public methods

/**
 * Sends a message to the specified web view.
 *
 * @param {NSString} Message
 * @param {UIWebView} Web view instance
 *
 * @return {void}
 */
- (void)sendMessage:(NSString *)message toWebView:(UIWebView *)webView 
{
    if (self.startupMessageQueue) { 
        [self.startupMessageQueue addObject:message]; 
    } else { 
        [self _doSendMessage:message toWebView: webView]; 
    }
}

/**
 * Resets the message queue.
 *
 * @return {void}
 */
- (void)resetQueue 
{
    self.startupMessageQueue = [[[NSMutableArray alloc] init] autorelease];
}

/**
 * Pushes custom headers that are used by the javascript bridge for AJAX requests.
 *
 * @param {NSMutableDictionary} Custom headers
 *
 * @return {void}
 */
- (void)pushRequestHeaders:(NSMutableDictionary *)headers
{
    if (!_requestHeaders) {
        _requestHeaders = [[NSMutableDictionary alloc] init];
    }

    self.requestHeaders = headers;
}

#pragma mark - Private methods

- (void)_doSendMessage:(NSString *)message toWebView:(UIWebView *)webView 
{
    message = [message stringByReplacingOccurrencesOfString:@"\\n" withString:@"\\\\n"];
    message = [message stringByReplacingOccurrencesOfString:@"\n" withString:@"\\\n"];
    message = [message stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    message = [message stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"WebViewJavascriptBridge._handleMessageFromObjC('%@');", message]];
}

- (void)_flushMessageQueueFromWebView:(UIWebView *)webView 
{
    NSString *messageQueueString = [webView stringByEvaluatingJavaScriptFromString:@"WebViewJavascriptBridge._fetchQueue();"];
    NSArray* messages = [messageQueueString componentsSeparatedByString:MESSAGE_SEPARATOR];
    for (id message in messages) {
        [self.delegate javascriptBridge:self receivedMessage:message fromWebView:webView];
    }
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView 
{
    NSString *js = [NSString stringWithFormat:@";(function() {"
        "if (window.WebViewJavascriptBridge) { return; };"
        "var _readyMessageIframe,"
        "     _sendMessageQueue = [],"
        "     _receiveMessageQueue = [],"
        "     _MESSAGE_SEPERATOR = '%@',"
        "     _CUSTOM_PROTOCOL_SCHEME = '%@',"
        "     _QUEUE_HAS_MESSAGE = '%@';"
        ""
        "function _createQueueReadyIframe(doc) {"
        "     _readyMessageIframe = doc.createElement('iframe');"
        "     _readyMessageIframe.style.display = 'none';"
        "     doc.documentElement.appendChild(_readyMessageIframe);"
        "}"
        ""
        "function _sendMessage(message) {"
        "     _sendMessageQueue.push(message);"
        "     _readyMessageIframe.src = _CUSTOM_PROTOCOL_SCHEME + '://' + _QUEUE_HAS_MESSAGE;"
        "};"
        ""
        "function _fetchQueue() {"
        "     var messageQueueString = _sendMessageQueue.join(_MESSAGE_SEPERATOR);"
        "     _sendMessageQueue = [];"
        "     return messageQueueString;"
        "};"
        ""
        "function _setMessageHandler(messageHandler) {"
        "     if (WebViewJavascriptBridge._messageHandler) { return alert('WebViewJavascriptBridge.setMessageHandler called twice'); }"
        "     WebViewJavascriptBridge._messageHandler = messageHandler;"
        "     var receivedMessages = _receiveMessageQueue;"
        "     _receiveMessageQueue = null;"
        "     for (var i=0; i<receivedMessages.length; i++) {"
        "         messageHandler(receivedMessages[i]);"
        "     }"
        "};"
        ""
        "function _handleMessageFromObjC(message) {"
        "     if (_receiveMessageQueue) { _receiveMessageQueue.push(message); }"
        "     else { WebViewJavascriptBridge._messageHandler(message); }"
        "};"
        ""
        "window.WebViewJavascriptBridge = {"
        "     setMessageHandler: _setMessageHandler,"
        "     sendMessage: _sendMessage,"
        "     _fetchQueue: _fetchQueue,"
        "     _handleMessageFromObjC: _handleMessageFromObjC"
        "};"
        ""
        "window.WebViewHeaders = {};"
        ""
        "XMLHttpRequest.prototype.open = (function() {"
        "     var base = XMLHttpRequest.prototype.open;"
        "     return function() {"
        "          base.apply(this, arguments);"
        "          for (var name in WebViewHeaders) {"
        "               if (WebViewHeaders.hasOwnProperty(name)) {"
        "                    try { this.setRequestHeader(name, WebViewHeaders[name]); }"
        "                    catch(e) { }"
        "               }"
        "          }"
        "     }"
        "})();"
        ""
        "var doc = document;"
        "_createQueueReadyIframe(doc);"
        "var readyEvent = doc.createEvent('Events');"
        "readyEvent.initEvent('WebViewJavascriptBridgeReady');"
        "doc.dispatchEvent(readyEvent);"
        ""
        "})();",
        MESSAGE_SEPARATOR,
        CUSTOM_PROTOCOL_SCHEME,
        QUEUE_HAS_MESSAGE];
    
    // Send javascript adapter to the webview
    if (![[webView stringByEvaluatingJavaScriptFromString:@"typeof WebViewJavascriptBridge == 'object'"] isEqualToString:@"true"]) {
        [webView stringByEvaluatingJavaScriptFromString:js];
    }
    
    // Send custom request headers to the javascript adapter
    for (id item in self.requestHeaders) {
        if ([item isKindOfClass:[NSString class]]) {
            [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"WebViewHeaders['%@']='%@';", item, [self.requestHeaders valueForKey:item]]];
        }
    }
    
    // Send messages from the queue
    for (id message in self.startupMessageQueue) {
        [self _doSendMessage:message toWebView: webView];
    }

    // Reset the startup message queue
    self.startupMessageQueue = nil;

    // Forward webview delegate page load events to the bridge
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:webView];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error 
{
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) 
    {
        [self.delegate webView:webView didFailLoadWithError:error];
    }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType 
{
    NSURL *url = [request URL];
    if (![[url scheme] isEqualToString:CUSTOM_PROTOCOL_SCHEME]) 
    {
        if (self.delegate != nil && [self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) 
        {
            return [self.delegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
        }
        return YES;
    }

    if ([[url host] isEqualToString:QUEUE_HAS_MESSAGE]) 
    {
        [self _flushMessageQueueFromWebView: webView];
    } else {
        NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@://%@", CUSTOM_PROTOCOL_SCHEME, [url path]);
    }

    return NO;
}

- (void)webViewDidStartLoad:(UIWebView *)webView 
{
    if (self.delegate != nil && [self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) 
    {
        [self.delegate webViewDidStartLoad:webView];
    }
}

#pragma mark - Dealloc

- (void)dealloc 
{
    self.delegate = nil;
    
    [_requestHeaders release]; _requestHeaders = nil;
    [_startupMessageQueue release]; _startupMessageQueue = nil;
    
    [super dealloc];
}

@end
