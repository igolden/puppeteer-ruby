require 'thread'

# https://github.com/puppeteer/puppeteer/blob/master/lib/DOMWorld.js
class Puppeteer::DOMWorld
  using Puppeteer::AsyncAwaitBehavior

  # on state: initialized
  #   context is nil.
  #   available_context blocks until context is set.
  # on state: resolved
  #   context is set
  #   available_context returns context immediately.
  class ContextResolver
    def initialize
      @queue = Queue.new
    end

    def resolve(context)
      if context.nil?
        raise ArgumentError.new("context should not be nil")
      end
      @queue.push(context)
    end

    def resolved?
      !!@context
    end

    def available_context
      @context ||= @queue.pop
    end
  end

  # @param {!Puppeteer.FrameManager} frameManager
  # @param {!Puppeteer.Frame} frame
  # @param {!Puppeteer.TimeoutSettings} timeoutSettings
  def initialize(frame_manager, frame, timeout_settings)
    @frame_manager = frame_manager
    @frame = frame
    @timeout_settings = timeout_settings
    @context_resolver = ContextResolver.new
    @wait_tasks = Set.new
    @detached = false
  end

  attr_reader :frame

  # @param {?Puppeteer.ExecutionContext} context
  def context=(context)
    if context
      @context_resolver.resolve(context)
    #   for (const waitTask of this._waitTasks)
    #     waitTask.rerun();
    else
      @document = nil
      @context_resolver = ContextResolver.new
    end
  end

  def has_context?
    @context_resolver.resolved?
  end

  private def detach
    @detached = true
    @wait_tasks.each do |wait_task|
      wait_task.terminate(Puppeteer::WaitTask::TerminatedError.new('waitForFunction failed: frame got detached.'))
    end
  end

  class DetachedError < StandardError ; end

  # @return {!Promise<!Puppeteer.ExecutionContext>}
  def execution_context
    if @detached
      raise DetachedError.new("Execution Context is not available in detached frame \"#{@frame.url}\" (are you trying to evaluate?)")
    end
    @context_resolver.available_context
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<!Puppeteer.JSHandle>}
  def evaluate_handle(page_function, *args)
    execution_context.evaluate_handle(page_function, *args)
  end

  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<*>}
  def evaluate(page_function, *args)
    execution_context.evaluate(page_function, *args)
  end

  # `$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<?Puppeteer.ElementHandle>}
  def S(selector)
    document.S(selector)
  end

  private def document
    @document ||= execution_context.evaluate_handle('document').as_element
  end

  # `$x()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} expression
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def Sx(expression)
    document.Sx(expression)
  end

  # `$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def Seval(selector, page_function, *args)
    document.Seval(selector, page_function, *args)
  end

  # `$$eval()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @param {Function|string} pageFunction
  # @param {!Array<*>} args
  # @return {!Promise<(!Object|undefined)>}
  def SSeval(selector, page_function, *args)
    document.SSeval(selector, page_function, *args)
  end

  # `$$()` in JavaScript. $ is not allowed to use as a method name in Ruby.
  # @param {string} selector
  # @return {!Promise<!Array<!Puppeteer.ElementHandle>>}
  def SS(selector)
    document.SS(selector)
  end

  # /**
  #  * @return {!Promise<String>}
  #  */
  # async content() {
  #   return await this.evaluate(() => {
  #     let retVal = '';
  #     if (document.doctype)
  #       retVal = new XMLSerializer().serializeToString(document.doctype);
  #     if (document.documentElement)
  #       retVal += document.documentElement.outerHTML;
  #     return retVal;
  #   });
  # }

  # /**
  #  * @param {string} html
  #  * @param {!{timeout?: number, waitUntil?: string|!Array<string>}=} options
  #  */
  # async setContent(html, options = {}) {
  #   const {
  #     waitUntil = ['load'],
  #     timeout = this._timeoutSettings.navigationTimeout(),
  #   } = options;
  #   // We rely upon the fact that document.open() will reset frame lifecycle with "init"
  #   // lifecycle event. @see https://crrev.com/608658
  #   await this.evaluate(html => {
  #     document.open();
  #     document.write(html);
  #     document.close();
  #   }, html);
  #   const watcher = new LifecycleWatcher(this._frameManager, this._frame, waitUntil, timeout);
  #   const error = await Promise.race([
  #     watcher.timeoutOrTerminationPromise(),
  #     watcher.lifecyclePromise(),
  #   ]);
  #   watcher.dispose();
  #   if (error)
  #     throw error;
  # }

  # /**
  #  * @param {!{url?: string, path?: string, content?: string, type?: string}} options
  #  * @return {!Promise<!Puppeteer.ElementHandle>}
  #  */
  # async addScriptTag(options) {
  #   const {
  #     url = null,
  #     path = null,
  #     content = null,
  #     type = ''
  #   } = options;
  #   if (url !== null) {
  #     try {
  #       const context = await this.executionContext();
  #       return (await context.evaluateHandle(addScriptUrl, url, type)).asElement();
  #     } catch (error) {
  #       throw new Error(`Loading script from ${url} failed`);
  #     }
  #   }

  #   if (path !== null) {
  #     let contents = await readFileAsync(path, 'utf8');
  #     contents += '//# sourceURL=' + path.replace(/\n/g, '');
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addScriptContent, contents, type)).asElement();
  #   }

  #   if (content !== null) {
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addScriptContent, content, type)).asElement();
  #   }

  #   throw new Error('Provide an object with a `url`, `path` or `content` property');

  #   /**
  #    * @param {string} url
  #    * @param {string} type
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addScriptUrl(url, type) {
  #     const script = document.createElement('script');
  #     script.src = url;
  #     if (type)
  #       script.type = type;
  #     const promise = new Promise((res, rej) => {
  #       script.onload = res;
  #       script.onerror = rej;
  #     });
  #     document.head.appendChild(script);
  #     await promise;
  #     return script;
  #   }

  #   /**
  #    * @param {string} content
  #    * @param {string} type
  #    * @return {!HTMLElement}
  #    */
  #   function addScriptContent(content, type = 'text/javascript') {
  #     const script = document.createElement('script');
  #     script.type = type;
  #     script.text = content;
  #     let error = null;
  #     script.onerror = e => error = e;
  #     document.head.appendChild(script);
  #     if (error)
  #       throw error;
  #     return script;
  #   }
  # }

  # /**
  #  * @param {!{url?: string, path?: string, content?: string}} options
  #  * @return {!Promise<!Puppeteer.ElementHandle>}
  #  */
  # async addStyleTag(options) {
  #   const {
  #     url = null,
  #     path = null,
  #     content = null
  #   } = options;
  #   if (url !== null) {
  #     try {
  #       const context = await this.executionContext();
  #       return (await context.evaluateHandle(addStyleUrl, url)).asElement();
  #     } catch (error) {
  #       throw new Error(`Loading style from ${url} failed`);
  #     }
  #   }

  #   if (path !== null) {
  #     let contents = await readFileAsync(path, 'utf8');
  #     contents += '/*# sourceURL=' + path.replace(/\n/g, '') + '*/';
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addStyleContent, contents)).asElement();
  #   }

  #   if (content !== null) {
  #     const context = await this.executionContext();
  #     return (await context.evaluateHandle(addStyleContent, content)).asElement();
  #   }

  #   throw new Error('Provide an object with a `url`, `path` or `content` property');

  #   /**
  #    * @param {string} url
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addStyleUrl(url) {
  #     const link = document.createElement('link');
  #     link.rel = 'stylesheet';
  #     link.href = url;
  #     const promise = new Promise((res, rej) => {
  #       link.onload = res;
  #       link.onerror = rej;
  #     });
  #     document.head.appendChild(link);
  #     await promise;
  #     return link;
  #   }

  #   /**
  #    * @param {string} content
  #    * @return {!Promise<!HTMLElement>}
  #    */
  #   async function addStyleContent(content) {
  #     const style = document.createElement('style');
  #     style.type = 'text/css';
  #     style.appendChild(document.createTextNode(content));
  #     const promise = new Promise((res, rej) => {
  #       style.onload = res;
  #       style.onerror = rej;
  #     });
  #     document.head.appendChild(style);
  #     await promise;
  #     return style;
  #   }
  # }

  # /**
  #  * @param {string} selector
  #  * @param {!{delay?: number, button?: "left"|"right"|"middle", clickCount?: number}=} options
  #  */
  # async click(selector, options) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.click(options);
  #   await handle.dispose();
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async focus(selector) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.focus();
  #   await handle.dispose();
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async hover(selector) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.hover();
  #   await handle.dispose();
  # }

  # /**
  #  * @param {string} selector
  #  * @param {!Array<string>} values
  #  * @return {!Promise<!Array<string>>}
  #  */
  # async select(selector, ...values) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   const result = await handle.select(...values);
  #   await handle.dispose();
  #   return result;
  # }

  # /**
  #  * @param {string} selector
  #  */
  # async tap(selector) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.tap();
  #   await handle.dispose();
  # }

  # /**
  #  * @param {string} selector
  #  * @param {string} text
  #  * @param {{delay: (number|undefined)}=} options
  #  */
  # async type(selector, text, options) {
  #   const handle = await this.$(selector);
  #   assert(handle, 'No node found for selector: ' + selector);
  #   await handle.type(text, options);
  #   await handle.dispose();
  # }

  # /**
  #  * @param {string} selector
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  #  * @return {!Promise<?Puppeteer.ElementHandle>}
  #  */
  # waitForSelector(selector, options) {
  #   return this._waitForSelectorOrXPath(selector, false, options);
  # }

  # /**
  #  * @param {string} xpath
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  #  * @return {!Promise<?Puppeteer.ElementHandle>}
  #  */
  # waitForXPath(xpath, options) {
  #   return this._waitForSelectorOrXPath(xpath, true, options);
  # }

  # /**
  #  * @param {Function|string} pageFunction
  #  * @param {!{polling?: string|number, timeout?: number}=} options
  #  * @return {!Promise<!Puppeteer.JSHandle>}
  #  */
  # waitForFunction(pageFunction, options = {}, ...args) {
  #   const {
  #     polling = 'raf',
  #     timeout = this._timeoutSettings.timeout(),
  #   } = options;
  #   return new WaitTask(this, pageFunction, 'function', polling, timeout, ...args).promise;
  # }

  # /**
  #  * @return {!Promise<string>}
  #  */
  # async title() {
  #   return this.evaluate(() => document.title);
  # }

  # /**
  #  * @param {string} selectorOrXPath
  #  * @param {boolean} isXPath
  #  * @param {!{visible?: boolean, hidden?: boolean, timeout?: number}=} options
  #  * @return {!Promise<?Puppeteer.ElementHandle>}
  #  */
  # async _waitForSelectorOrXPath(selectorOrXPath, isXPath, options = {}) {
  #   const {
  #     visible: waitForVisible = false,
  #     hidden: waitForHidden = false,
  #     timeout = this._timeoutSettings.timeout(),
  #   } = options;
  #   const polling = waitForVisible || waitForHidden ? 'raf' : 'mutation';
  #   const title = `${isXPath ? 'XPath' : 'selector'} "${selectorOrXPath}"${waitForHidden ? ' to be hidden' : ''}`;
  #   const waitTask = new WaitTask(this, predicate, title, polling, timeout, selectorOrXPath, isXPath, waitForVisible, waitForHidden);
  #   const handle = await waitTask.promise;
  #   if (!handle.asElement()) {
  #     await handle.dispose();
  #     return null;
  #   }
  #   return handle.asElement();

  #   /**
  #    * @param {string} selectorOrXPath
  #    * @param {boolean} isXPath
  #    * @param {boolean} waitForVisible
  #    * @param {boolean} waitForHidden
  #    * @return {?Node|boolean}
  #    */
  #   function predicate(selectorOrXPath, isXPath, waitForVisible, waitForHidden) {
  #     const node = isXPath
  #       ? document.evaluate(selectorOrXPath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue
  #       : document.querySelector(selectorOrXPath);
  #     if (!node)
  #       return waitForHidden;
  #     if (!waitForVisible && !waitForHidden)
  #       return node;
  #     const element = /** @type {Element} */ (node.nodeType === Node.TEXT_NODE ? node.parentElement : node);

  #     const style = window.getComputedStyle(element);
  #     const isVisible = style && style.visibility !== 'hidden' && hasVisibleBoundingBox();
  #     const success = (waitForVisible === isVisible || waitForHidden === !isVisible);
  #     return success ? node : null;

  #     /**
  #      * @return {boolean}
  #      */
  #     function hasVisibleBoundingBox() {
  #       const rect = element.getBoundingClientRect();
  #       return !!(rect.top || rect.bottom || rect.width || rect.height);
  #     }
  #   }
  # }
end
