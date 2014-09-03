//
//  DZNWebViewController.m
//  DZNWebViewController
//  https://github.com/dzenbot/DZNWebViewController
//
//  Created by Ignacio Romero Zurbuchen on 10/25/13.
//  Copyright (c) 2014 DZN Labs. All rights reserved.
//  Licence: MIT-Licence
//

#import "DZNWebViewController.h"
#import "DZNPolyActivity.h"

#import <NJKWebViewProgress/NJKWebViewProgressView.h>
#import <NJKWebViewProgress/NJKWebViewProgress.h>

#define kDZNWebViewControllerContentTypeImage @"image"
#define kDZNWebViewControllerContentTypeLink @"link"

@interface DZNWebViewController () <UIGestureRecognizerDelegate, NJKWebViewProgressDelegate>
{
    NJKWebViewProgress *_progressProxy;
    
    int _loadBalance;
}
@property (nonatomic, strong) NJKWebViewProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;
@end

@implementation DZNWebViewController
@synthesize URL = _URL;

- (id)init
{
    self = [super init];
    if (self) {
        _loadingStyle = DZNWebViewControllerLoadingStyleProgressView;
    }
    return self;
}

- (id)initWithURL:(NSURL *)URL
{
    NSParameterAssert(URL);
    NSAssert(URL != nil, @"Invalid URL");
    NSAssert(URL.scheme != nil, @"URL has no scheme");

    self = [self init];
    if (self) {
        _URL = URL;
    }
    return self;
}

- (id)initWithFileURL:(NSURL *)URL
{
    return [self initWithURL:URL];
}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view = self.webView;
    if ([self respondsToSelector:@selector(setAutomaticallyAdjustsScrollViewInsets:)]) {
        self.automaticallyAdjustsScrollViewInsets = YES;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
    
    [self clearProgressViewAnimated:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
    
    [self stopLoading];
}


#pragma mark - Getter methods

- (UIWebView *)webView
{
    if (!_webView)
    {
        _webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
        _webView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        _webView.backgroundColor = [UIColor whiteColor];
        
        if (_loadingStyle == DZNWebViewControllerLoadingStyleProgressView)
        {
            _progressProxy = [[NJKWebViewProgress alloc] init];
            _webView.delegate = _progressProxy;
            _progressProxy.webViewProxyDelegate = self;
            _progressProxy.progressDelegate = self;
        }
        else {
            _webView.delegate = self;
        }
    }
    return _webView;
}

- (NJKWebViewProgressView *)progressView
{
    if (!_progressView && _loadingStyle == DZNWebViewControllerLoadingStyleProgressView)
    {
        CGFloat progressBarHeight = 2.5f;
        CGSize navigationBarSize = self.navigationController.navigationBar.bounds.size;
        CGRect barFrame = CGRectMake(0, navigationBarSize.height - progressBarHeight, navigationBarSize.width, progressBarHeight);
        _progressView = [[NJKWebViewProgressView alloc] initWithFrame:barFrame];
        
        [self.navigationController.navigationBar addSubview:_progressView];
    }
    return _progressView;
}

- (UIActivityIndicatorView *)activityIndicatorView
{
    if (!_activityIndicatorView)
    {
        _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _activityIndicatorView.hidesWhenStopped = YES;
    }
    return _activityIndicatorView;
}

- (UIFont *)titleFont
{
    if (!_titleFont) {
        return [[UINavigationBar appearance].titleTextAttributes objectForKey:NSFontAttributeName];
    }
    
    return _titleFont;
}

- (UIColor *)titleColor
{
    if (!_titleColor) {
        return [[UINavigationBar appearance].titleTextAttributes objectForKey:NSForegroundColorAttributeName];
    }
    
    return _titleColor;
}

- (NSString *)pageTitle
{
    NSString *js = @"document.body.style.webkitTouchCallout = 'none'; document.getElementsByTagName('title')[0].textContent;";
    NSString *title = [_webView stringByEvaluatingJavaScriptFromString:js];
    return [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSURL *)URL
{
    return _URL;
}

- (CGSize)HTLMWindowSize
{
    CGSize size = CGSizeZero;
    size.width = [[_webView stringByEvaluatingJavaScriptFromString:@"window.innerWidth"] floatValue];
    size.height = [[_webView stringByEvaluatingJavaScriptFromString:@"window.innerHeight"] floatValue];
    return size;
}

- (CGPoint)convertPointToHTMLSystem:(CGPoint)point
{
    CGSize viewSize = _webView.frame.size;
    CGSize windowSize = [self HTLMWindowSize];
    
    CGPoint scaledPoint = CGPointZero;
    CGFloat factor = windowSize.width / viewSize.width;
    
    scaledPoint.x = point.x * factor;
    scaledPoint.y = point.y * factor;
    
    return scaledPoint;
}

#pragma mark - Setter methods

- (void)setURL:(NSURL *)URL
{
    [self startRequestWithURL:URL];
}

- (void)setViewTitle:(NSString *)title
{
    self.navigationItem.title = title;
}

/*
 * Sets the request errors with an alert view.
 */
- (void)setLoadingError:(NSError *)error
{
    switch (error.code) {
        case NSURLErrorUnknown:
        case NSURLErrorCancelled:
            return;
    }
    
    [self setActivityIndicatorsVisible:NO];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil) message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles: nil];
    [alert show];
}

/*
 * Toggles the activity indicators on the status bar & footer view.
 */
- (void)setActivityIndicatorsVisible:(BOOL)visible
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = visible;
    
    if (_loadingStyle != DZNWebViewControllerLoadingStyleActivityIndicator) {
        return;
    }
    
    if (visible) [_activityIndicatorView startAnimating];
    else [_activityIndicatorView stopAnimating];
}

#pragma mark - DZNWebViewController methods

- (void)startRequestWithURL:(NSURL *)URL
{
    _loadBalance = 0;
    
    if (![self.webView.request.URL isFileURL]) {
        [_webView loadRequest:[[NSURLRequest alloc] initWithURL:URL]];
    }
    else {
        NSData *data = [[NSData alloc] initWithContentsOfURL:URL];
        NSString *HTMLString = [[NSString alloc] initWithData:data encoding:NSStringEncodingConversionAllowLossy];
        
        [_webView loadHTMLString:HTMLString baseURL:nil];
    }
}

- (void)injectJavaScript
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"inpector-script" ofType:@"js"];
    NSString *script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    
    [_webView stringByEvaluatingJavaScriptFromString:script];
}

- (void)handleInteractivePopGesture:(UIGestureRecognizer *)gesture
{
    NSLog(@"%s : %@",__FUNCTION__, gesture);
}

- (void)clearProgressViewAnimated:(BOOL)animated
{
    if (!_progressView) {
        return;
    }
    
    [UIView animateWithDuration:animated ? 0.25 : 0.0
                     animations:^{
                         _progressView.alpha = 0;
                     } completion:^(BOOL finished) {
                         [_progressView removeFromSuperview];
                     }];
}

- (void)stopLoading
{
    [self.webView stopLoading];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}


#pragma mark - UIWebViewDelegate methods

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{    
    if (request.URL) {
        return YES;
    }
    
    return NO;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    // load balance is use to see if the load was completed end of the site
    _loadBalance++;
    
    if (_loadBalance == 1) {
        [self setActivityIndicatorsVisible:YES];
    }
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (_loadBalance >= 1) _loadBalance--;
    else if (_loadBalance < 0) _loadBalance = 0;

    if (_loadBalance == 0) {
        [self setActivityIndicatorsVisible:NO];
    }
    
    [self setViewTitle:[self pageTitle]];
    
    if ([webView.request.URL isFileURL] && _loadingStyle == DZNWebViewControllerLoadingStyleProgressView) {
        [_progressView setProgress:1.0 animated:YES];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    _loadBalance = 0;
    [self setLoadingError:error];
}

#pragma mark - NJKWebViewProgressDelegate methods

- (void)webViewProgress:(NJKWebViewProgress *)webViewProgress updateProgress:(float)progress
{
    [self.progressView setProgress:progress animated:YES];
}

#pragma mark - View lifeterm

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)dealloc
{
    _activityIndicatorView = nil;
    
    _webView = nil;
    _URL = nil;
}


#pragma mark - View Auto-Rotation

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

@end
